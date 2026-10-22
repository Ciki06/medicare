'use strict';
const {randomInt, randomBytes, createHmac, timingSafeEqual}=require('node:crypto');
const functions=require('firebase-functions');
const admin=require('firebase-admin');
const nodemailer=require('nodemailer');

const CODE_LIFETIME=10*60*1000;
const COOLDOWN=60*1000;
const WINDOW=60*60*1000;
const MAX_CODE_ATTEMPTS=5;
const SECRETS=['PASSWORD_RESET_EMAIL_USER','PASSWORD_RESET_EMAIL_PASSWORD','PASSWORD_RESET_CODE_SECRET'];
const error=(code,message)=>new functions.https.HttpsError(code,message);
function normalizeEmail(value){return typeof value==='string'?value.trim().toLowerCase():'';}
function validEmail(value){return value.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);}
function digest(secret,value){return createHmac('sha256',secret).update(value).digest('hex');}
function equalHash(a,b){
  if(typeof a!=='string'||typeof b!=='string'||! /^[a-f0-9]{64}$/.test(a)||! /^[a-f0-9]{64}$/.test(b))return false;
  return timingSafeEqual(Buffer.from(a,'hex'),Buffer.from(b,'hex'));
}
function windowState(data,now){
  return data&&now-data.windowStartedAt<WINDOW&&now>=data.windowStartedAt
    ? {windowStartedAt:data.windowStartedAt,requests:data.requests||0,verifications:data.verifications||0,failedCodes:data.failedCodes||0}
    : {windowStartedAt:now,requests:0,verifications:0,failedCodes:0};
}

// Kept injectable so tests use the Auth and Firestore emulators and capture
// outgoing email without emailing real people or changing live accounts.
function createPasswordResetService({db,auth,secret,sendEmail,now=Date.now,collection='_password_reset_challenges',minimumResponseMs=1200}){
  function configuration(){
    const value=secret();
    if(typeof value!=='string'||value.length<32)throw error('failed-precondition','Password reset email is not configured yet.');
    return value;
  }
  function references(email,context,key){
    const ip=context?.rawRequest?.ip||context?.rawRequest?.socket?.remoteAddress||'unknown';
    return {
      challenge:db.collection(collection).doc(`email_${digest(key,email)}`),
      address:db.collection(collection).doc(`ip_${digest(key,String(ip))}`),
    };
  }
  async function request(data,context){
    const started=Date.now(),email=normalizeEmail(data?.email),key=configuration();
    if(!validEmail(email))throw error('invalid-argument','Enter a valid email address.');
    let user=null;
    try{user=await auth.getUserByEmail(email);}catch(failure){
      if(failure.code!=='auth/user-not-found')throw error('unavailable','Could not send the code. Please try again later.');
    }
    const time=now(),challengeId=randomBytes(32).toString('base64url');
    const code=randomInt(10000).toString().padStart(4,'0');
    const {challenge,address}=references(email,context,key);
    await db.runTransaction(async transaction=>{
      const [previous,ip]=await Promise.all([transaction.get(challenge),transaction.get(address)]);
      const old=previous.data()||{},accountWindow=windowState(old,time),ipWindow=windowState(ip.data(),time);
      if(time-(old.lastSentAt||0)<COOLDOWN||accountWindow.requests>=3||ipWindow.requests>=10){
        throw error('resource-exhausted','Too many requests. Please wait before requesting another code.');
      }
      const deleteAfter=admin.firestore.Timestamp.fromMillis(time+2*WINDOW);
      transaction.set(challenge,{
        ...accountWindow,requests:accountWindow.requests+1,type:'challenge',challengeId,
        userUid:user&&!user.disabled?user.uid:null,
        codeHash:digest(key,`${email}:${challengeId}:${code}`),attempts:0,state:'active',
        lastSentAt:time,codeExpiresAt:time+CODE_LIFETIME,deleteAfter,
      });
      transaction.set(address,{...ipWindow,requests:ipWindow.requests+1,type:'rate_limit',deleteAfter});
    });
    if(user&&!user.disabled){
      try{await sendEmail(email,code);}catch(failure){
        await db.runTransaction(async transaction=>{
          const current=await transaction.get(challenge);
          if(current.data()?.challengeId===challengeId){
            transaction.update(challenge,{state:'failed',codeHash:admin.firestore.FieldValue.delete()});
          }
        });
        // Mail errors may contain SMTP credentials. Log only a short category.
        functions.logger.warn('Password reset email delivery failed',{code:String(failure.code||'mail-error').slice(0,32)});
        throw error('unavailable','Could not send the code. Please try again later.');
      }
    }
    // Unknown/disabled accounts get the same response and an opaque challenge.
    const remaining=minimumResponseMs-(Date.now()-started);
    if(remaining>0)await new Promise(resolve=>setTimeout(resolve,remaining));
    return {challengeId,expiresInSeconds:CODE_LIFETIME/1000,resendAfterSeconds:COOLDOWN/1000};
  }
  async function verify(data,context){
    const email=normalizeEmail(data?.email),code=data?.code,challengeId=data?.challengeId,key=configuration();
    if(!validEmail(email)||typeof code!=='string'||!/^\d{4}$/.test(code)||
        typeof challengeId!=='string'||!/^[-\w]{43}$/.test(challengeId)){
      throw error('invalid-argument','Enter the four-digit code from your email.');
    }
    const {challenge,address}=references(email,context,key),time=now();
    const result=await db.runTransaction(async transaction=>{
      const [snapshot,ip]=await Promise.all([transaction.get(challenge),transaction.get(address)]);
      const value=snapshot.data(),ipWindow=windowState(ip.data(),time);
      if(ipWindow.verifications>=30)return {limited:true};
      transaction.set(address,{...ipWindow,verifications:ipWindow.verifications+1,
        type:'rate_limit',deleteAfter:admin.firestore.Timestamp.fromMillis(time+2*WINDOW)});
      if(!value||value.challengeId!==challengeId||value.state!=='active'||
          value.codeExpiresAt<=time||value.attempts>=MAX_CODE_ATTEMPTS)return {};
      const accountWindow=windowState(value,time);
      if(accountWindow.failedCodes>=10)return {limited:true};
      const matches=equalHash(value.codeHash,digest(key,`${email}:${challengeId}:${code}`));
      if(!matches||!value.userUid){
        const attempts=value.attempts+1;
        transaction.update(challenge,{...accountWindow,failedCodes:accountWindow.failedCodes+1,
          attempts,state:attempts>=MAX_CODE_ATTEMPTS?'locked':'active'});
        // Returning an error outcome commits the attempt counter. Throwing
        // inside the transaction here would roll back brute-force protection.
        return {};
      }
      transaction.update(challenge,{state:'consumed',codeHash:admin.firestore.FieldValue.delete(),verifiedAt:time});
      return {uid:value.userUid};
    });
    if(result.limited)throw error('resource-exhausted','Too many attempts. Please try again later.');
    if(!result.uid)throw error('invalid-argument','The code is incorrect or has expired. Request a new code if needed.');
    try{
      const user=await auth.getUser(result.uid);
      if(user.disabled||normalizeEmail(user.email)!==email)throw new Error('Account changed');
      // Firebase owns the final, single-use password reset credential and
      // password-policy checks. It is issued only after successful OTP proof.
      const link=await auth.generatePasswordResetLink(email);
      const resetCode=new URL(link).searchParams.get('oobCode');
      if(!resetCode)throw new Error('No reset credential');
      return {email,resetCode};
    }catch(_){throw error('unavailable','Could not verify the code. Request a new code and try again.');}
  }
  return {request,verify};
}

function mailer(){
  const user=process.env.PASSWORD_RESET_EMAIL_USER,password=process.env.PASSWORD_RESET_EMAIL_PASSWORD;
  if(!validEmail(normalizeEmail(user))||!password)throw error('failed-precondition','Password reset email is not configured yet.');
  const host=process.env.PASSWORD_RESET_SMTP_HOST||'smtp.gmail.com';
  const port=Number(process.env.PASSWORD_RESET_SMTP_PORT||465);
  return {user,transport:nodemailer.createTransport({host,port,secure:port===465,
    requireTLS:port!==465,auth:{user,pass:host==='smtp.gmail.com'?password.replace(/\s/g,''):password},
    connectionTimeout:10000,greetingTimeout:10000,socketTimeout:15000})};
}
async function sendEmail(email,code){
  const {user,transport}=mailer();
  await transport.sendMail({from:{name:'Medicare',address:user},to:email,
    subject:'Your Medicare verification code',
    text:`Your Medicare password reset code is ${code}.\n\nEnter this four-digit code in the Medicare app. It expires in 10 minutes.\n\nIf you did not request this reset, ignore this email. Your password has not changed.`,
    html:`<div style="font-family:Arial,sans-serif;color:#203e7c"><h2>Reset your Medicare password</h2><p>Enter this four-digit code in the Medicare app:</p><p style="font-size:32px;font-weight:bold;letter-spacing:8px">${code}</p><p>This code expires in 10 minutes.</p><p>If you did not request this reset, ignore this email. Your password has not changed.</p></div>`});
}
const service=createPasswordResetService({db:admin.firestore(),auth:admin.auth(),
  secret:()=>process.env.PASSWORD_RESET_CODE_SECRET,sendEmail});
const region=functions.region('asia-southeast1');
exports.requestPasswordResetCode=region.runWith({secrets:SECRETS,timeoutSeconds:45}).https.onCall(async(data,context)=>{
  mailer(); // Reject missing sender configuration consistently, for every email.
  return service.request(data,context);
});
exports.verifyPasswordResetCode=region.runWith({secrets:['PASSWORD_RESET_CODE_SECRET'],timeoutSeconds:45}).https.onCall(service.verify);
exports._test={createPasswordResetService,normalizeEmail,validEmail,equalHash,CODE_LIFETIME,COOLDOWN};
