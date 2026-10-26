'use strict';

// The canonical persisted contract. Auth UIDs are strings; domain document
// names are positive safe integer strings shared with SQLite record keys.
// Optional fields are omitted, never persisted as null. Sync state is local.
const profile = {
  uid: 'Auth UID string (same as document name)',
  role: 'caregiver | patient | family | pharmacist',
  name: 'string', email: 'lowercase string', createdAt: 'UTC ISO-8601 string',
  updatedAt: 'UTC ISO-8601 string', caregiverId: 'Auth UID string',
  phone: 'string', dateOfBirth: 'YYYY-MM-DD string', gender: 'string',
  address: 'string', registeredId: 'string', icNumber: 'string',
  medicalHistory: 'string[]', medicalNotes: 'string', profilePicUrl: 'URL string',
  shortId: 'string', relationship: 'string', linkedPatientIds: 'Auth UID string[]',
  linkedPatientEmails: 'lowercase email string[] (server-maintained display cache)',
  fcmTokens: 'FCM token string[]', fcmTokenUpdatedAt: 'Firestore Timestamp',
};
const collections = {
  users: {key: 'Firebase Authentication UID', fields: profile,
    required: ['uid','role','name','email','createdAt','updatedAt'],
    note:'Family and pharmacist self-signup starts unassigned. Only the caregiver can enroll these accounts and change family patient links. A family member can edit personal details while preserving the same linked-patient set; family lookup is limited to already linked patients.'},
  medications: {key: 'positive safe integer string', fields: {
    patientId:'Auth UID string', caregiverId:'Auth UID string', patientName:'string',
    name:'string', type:'string', days:'string[]', dosage:'string', time:'HH:mm string',
    timeZone:'IANA timezone string', startDate:'YYYY-MM-DD string', intervalDays:'positive integer',
    remindRefill:'boolean', remindThreshold:'nonnegative integer', currentStock:'nonnegative integer',
    imageUrl:'URL string', deletedAt:'epoch milliseconds integer', lastActionId:'numeric action document key string',
  }, required:['patientId','caregiverId','patientName','name','type','days','dosage','time','timeZone','intervalDays','remindRefill','currentStock'],
    tombstoneRequired:['patientId','caregiverId','name','deletedAt']},
  appointments: {key:'positive safe integer string', fields:{
    patientId:'Auth UID string', caregiverId:'Auth UID string', patientName:'string',
    title:'string', date:'YYYY-MM-DD string', time:'HH:mm string', location:'string',
    remindBefore:'nonnegative integer minutes', status:'scheduled | completed',
    reminderViewedFor:'optional current date|HH:mm|remindBefore reminder acknowledgement',
    deletedAt:'epoch milliseconds integer',
  }, required:['patientId','caregiverId','patientName','title','date','time','location','remindBefore','status']},
  medication_actions: {key:'positive safe integer string', fields:{
    patientId:'Auth UID string', medicationId:'positive safe integer',
    medicationName:'string', action:'taken | skipped | snoozed', timestamp:'epoch milliseconds integer',
    snoozeUntil:'epoch milliseconds integer',
  }, required:['patientId','medicationId','medicationName','action','timestamp']},
  moods: {key:'positive safe integer string', fields:{
    patientId:'Auth UID string', moodIndex:'integer 0..8', moodLabel:'string',
    emoji:'string', date:'YYYY-MM-DD string', timestamp:'epoch milliseconds integer',
  }, required:['patientId','moodIndex','moodLabel','emoji','date','timestamp']},
  refill_requests: {key:'positive safe integer string', fields:{
    patientId:'Auth UID string', caregiverId:'Auth UID string', pharmacyUid:'Auth UID string',
    medicationId:'positive safe integer', caregiverName:'string', patientName:'string',
    medicationName:'string', quantityLeft:'nonnegative integer', quantityRequested:'nonnegative integer (new requests must be positive; 0 means unspecified historical amount)',
    status:'pending | processing | ready_for_pickup | collected | rejected',
    requestedAt:'epoch milliseconds integer', updatedAt:'epoch milliseconds integer',
  }, required:['patientId','caregiverId','medicationId','caregiverName','patientName','medicationName','quantityLeft','quantityRequested','status','requestedAt']},
  sos_alerts: {key:'Firestore generated string', fields:{
    patientId:'Auth UID string', caregiverId:'Auth UID string or empty string when unassigned', patientName:'string',
    alertUserIds:'Auth UID string[] (server-resolved)', status:'active | acknowledged | stopped',
    createdAt:'epoch milliseconds integer', triggerSource:'in_app | home_widget',
    locationStatus:'pending | available | permission_denied | services_disabled | unavailable',
    latitude:'number -90..90', longitude:'number -180..180', locationAccuracy:'nonnegative number',
    locationCapturedAt:'epoch milliseconds integer', locationName:'string',
    acknowledgedAt:'Firestore Timestamp or epoch milliseconds', acknowledgedBy:'Auth UID string',
    recipientsResolvedAt:'Firestore Timestamp', dispatchStatus:'string', notifiedAt:'Firestore Timestamp',
    notificationRecipientCount:'integer', notificationDeviceCount:'integer',
    notificationSuccessCount:'integer', notificationFailureCount:'integer',
  }, required:['patientId','patientName','caregiverId','alertUserIds','status','createdAt','triggerSource','locationStatus']},
  'sos_alerts/{alertId}/responses': {key:'Firestore generated string', fields:{
    senderId:'Auth UID string', senderName:'string', senderRole:'caregiver | family',
    message:'string', createdAt:'Firestore Timestamp or epoch milliseconds',
  }, required:['senderId','senderName','senderRole','message','createdAt']},
  chats: {key:'two sorted participant Auth UIDs joined by underscore', fields:{
    participants:'Auth UID string[2]', lastMessage:'string', lastMessageSender:'sender display name string',
    lastMessageAt:'epoch milliseconds integer', unreadCount:'map<Auth UID, nonnegative integer>',
  }, required:['participants','lastMessage','lastMessageSender','lastMessageAt','unreadCount']},
  'chats/{chatId}/messages': {key:'Firestore generated string or sos_{alertId}', fields:{
    senderId:'Auth UID string', senderName:'string', text:'string', createdAt:'epoch milliseconds integer',
    type:'text | image | voice | sos_location (server only)', mediaUrl:'URL string',
    caption:'string', durationSeconds:'integer 1..3600', forwarded:'boolean',
    alertId:'SOS document key (server only)', mapUrl:'URL string or empty string (server only)',
    latitude:'number -90..90 or null (server GPS snapshot)', longitude:'number -180..180 or null (server GPS snapshot)',
    locationName:'approximate nearby address string (server only)', locationStatus:'GPS snapshot availability (server only)',
    locationAccuracy:'nonnegative meters or null (server only)', locationCapturedAt:'GPS capture epoch milliseconds or null (server only)',
  }, required:['senderId','senderName','text','createdAt']},
  'chats/{chatId}/presence': {key:'participant Auth UID', fields:{
    readThrough:'epoch milliseconds integer', typingAt:'epoch milliseconds integer',
  }, required:[]},
  calls: {key:'Firestore generated string', fields:{
    chatId:'chat document key', participants:'Auth UID string[2]', callerId:'Auth UID string',
    calleeId:'Auth UID string', callerName:'string', calleeName:'string',
    state:'preparing | ringing | accepted | rejected | ended', createdAt:'epoch milliseconds integer',
    expiresAt:'epoch milliseconds integer', offer:'map<type,sdp>', answer:'map<type,sdp>',
    acceptedAt:'epoch milliseconds integer', endedAt:'epoch milliseconds integer',
    endedBy:'Auth UID string', heartbeats:'map<Auth UID, epoch milliseconds>',
  }, required:['chatId','participants','callerId','calleeId','callerName','calleeName','state','createdAt','expiresAt']},
  'calls/{callId}/candidates': {key:'Firestore generated string', fields:{
    senderId:'Auth UID string', candidate:'string', sdpMid:'string or null', sdpMLineIndex:'integer or null',
  }, required:['senderId','candidate','sdpMid','sdpMLineIndex']},
  call_sessions: {key:'Auth UID (backend only)', fields:{
    callId:'call document key', expiresAt:'epoch milliseconds integer',
  }, required:['callId','expiresAt']},
  _account_provisioning: {key:'managed_ + SHA-256(caregiver Auth UID, zero separator, 32-hex request ID)',fields:{
    uid:'deterministic managed Auth UID string',caregiverId:'requesting caregiver Auth UID string',
    email:'lowercase requested email string',role:'patient | family | pharmacist',
    status:'pending | complete | retry',createdAt:'UTC ISO-8601 string',updatedAt:'UTC ISO-8601 string',
    lastErrorCode:'sanitized error code string; retry only',deleteAfter:'Firestore Timestamp; complete only, 7-day TTL',
  },required:['uid','caregiverId','email','role','status','createdAt','updatedAt'],
    note:'Private durable operation for retry-safe account creation. Incomplete operations do not expire. No passwords, tokens or raw request IDs are stored. Auth and Firestore are separate services; an interrupted Auth creation is reused on retry, never unsafely deleted.'},
  _password_reset_challenges: {key:'backend-only challenge key', fields:{
    type:'challenge | rate_limit', windowStartedAt:'epoch milliseconds integer',
    requests:'integer', verifications:'integer', failedCodes:'integer', challengeId:'opaque random string',
    userUid:'Auth UID string or null', codeHash:'HMAC hash string', attempts:'integer',
    state:'active | failed | locked | consumed', lastSentAt:'epoch milliseconds integer',
    codeExpiresAt:'epoch milliseconds integer', verifiedAt:'epoch milliseconds integer',
    deleteAfter:'Firestore Timestamp (TTL)',
  }, note:'Private challenge and rate-limit records; password-reset behavior unchanged.'},
};
const relationships = [
  {from:'Firebase Auth users',to:'users',field:'uid / document key',cardinality:'1 to 0..1 profile'},
  {from:'users (caregiver)',to:'users (patient/family/pharmacist)',field:'caregiverId',cardinality:'1 to 0..many'},
  {from:'users (family)',to:'users (patient)',field:'linkedPatientIds',cardinality:'many to many'},
  ...['medications','appointments','medication_actions','moods','refill_requests','sos_alerts'].map(to=>({from:'users (patient)',to,field:'patientId',cardinality:'1 to 0..many'})),
  ...['medications','appointments','refill_requests'].map(to=>({from:'users (caregiver)',to,field:'caregiverId',cardinality:'1 to 0..many'})),
  ...['medication_actions','refill_requests'].map(to=>({from:'medications',to,field:'medicationId',cardinality:'1 to 0..many'})),
  {from:'users (pharmacist)',to:'refill_requests',field:'pharmacyUid',cardinality:'1 to 0..many (optional assignment)'},
  {from:'chats',to:'chats/{chatId}/messages',field:'parent document path',cardinality:'1 to 0..many'},
  {from:'chats',to:'chats/{chatId}/presence',field:'parent path + participant UID',cardinality:'1 to 0..2'},
  {from:'sos_alerts',to:'sos_alerts/{alertId}/responses',field:'parent document path',cardinality:'1 to 0..many'},
  {from:'calls',to:'calls/{callId}/candidates',field:'parent document path',cardinality:'1 to 0..many'},
  {from:'chats',to:'calls',field:'chatId',cardinality:'1 to 0..many'},
  {from:'users (caregiver)',to:'sos_alerts',field:'caregiverId',cardinality:'1 to 0..many; optional when patient is unassigned'},
  {from:'medications',to:'medication_actions',field:'lastActionId',cardinality:'1 to 0..1 latest stock-consuming event'},
  {from:'users',to:'chats/{chatId}/messages',field:'senderId',cardinality:'1 to 0..many'},
  {from:'users',to:'sos_alerts/{alertId}/responses',field:'senderId',cardinality:'1 to 0..many'},
  {from:'users',to:'calls/{callId}/candidates',field:'senderId',cardinality:'1 to 0..many'},
  {from:'users',to:'chats/{chatId}/presence',field:'document key',cardinality:'1 to 0..many; at most 1 per chat'},
  {from:'calls',to:'call_sessions',field:'callId',cardinality:'1 to 0..2 participant reservations'},
  {from:'sos_alerts',to:'chats/{chatId}/messages',field:'alertId',cardinality:'1 to 0..many recipient chat entries'},
  {from:'users',to:'sos_alerts',field:'acknowledgedBy',cardinality:'1 to 0..many; optional on each alert'},
  {from:'users',to:'calls',field:'endedBy',cardinality:'1 to 0..many; optional on each call'},
  {from:'users',to:'calls',field:'heartbeats map keys',cardinality:'many to many; at most 2 users per call'},
  {from:'users (caregiver)',to:'_account_provisioning',field:'caregiverId',cardinality:'1 to 0..many requests'},
  {from:'_account_provisioning',to:'Firebase Auth users / users',field:'uid',cardinality:'1 to 0..1 managed account/profile while pending; exactly 1 when complete'},
];
module.exports = {version:1, collections, relationships};

