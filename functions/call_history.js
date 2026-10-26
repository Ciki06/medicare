'use strict';

const LIVE_STATES = ['preparing', 'ringing', 'accepted'];
function terminalState(call, action, uid, now) {
  if (call.expiresAt <= now) return call.acceptedAt ? 'ended' : call.state === 'preparing' ? 'cancelled' : 'missed';
  if (call.acceptedAt || call.state === 'accepted') return 'ended';
  return action === 'reject' || uid === call.calleeId ? 'rejected' : 'cancelled';
}
function callEvent(id, call) {
  return {
    type: 'call', callId: id, senderId: call.callerId, senderName: call.callerName,
    callerId: call.callerId, callerName: call.callerName,
    calleeId: call.calleeId, calleeName: call.calleeName,
    callStatus: call.state, createdAt: call.createdAt,
    acceptedAt: call.acceptedAt || null, endedAt: call.endedAt || null,
    durationSeconds: call.acceptedAt && call.endedAt ? Math.max(0, Math.floor((call.endedAt - call.acceptedAt) / 1000)) : 0,
    text: `Voice call: ${call.state === 'ended' && call.acceptedAt ? 'accepted' : call.state}`,
  };
}

// Called from the signaling transaction. One ID for the entire call lifecycle;
// no asynchronous trigger can overwrite a newer state or duplicate the event.
function writeCallEvent(tx, room, roomData, id, call, initial = false) {
  const event = callEvent(id, call);
  tx.set(room.collection('messages').doc(`call_${id}`), event);
  const updates = {};
  if (initial) updates[`unreadCount.${call.calleeId}`] = (roomData.unreadCount?.[call.calleeId] || 0) + 1;
  if ((roomData.lastMessageAt || 0) <= call.createdAt) {
    Object.assign(updates, {lastMessage: event.text, lastMessageSender: call.callerName, lastMessageAt: call.createdAt});
  }
  if (Object.keys(updates).length) tx.update(room, updates);
}

module.exports = {LIVE_STATES, terminalState, callEvent, writeCallEvent};
