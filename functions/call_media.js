'use strict';

// Only the callable function writes this state. A user may enable their own
// camera; no request can grant consent on behalf of the other participant.
class CallMediaError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function initialMedia(participants) {
  return {version: 1, mode: 'voice', cameras: Object.fromEntries(participants.map(uid => [uid, false])), revision: 0};
}

function videoCapabilities(call) {
  return Object.fromEntries(call.participants.map(uid => [uid, call.videoCapabilities?.[uid] === true]));
}

function currentMedia(call) {
  const stored = call.media;
  const mode = stored?.version === 1 && stored.mode === 'video' ? 'video' : 'voice';
  return {
    version: 1,
    mode,
    cameras: Object.fromEntries(call.participants.map(uid => [uid, mode === 'video' && stored?.cameras?.[uid] === true])),
    revision: Number.isSafeInteger(stored?.revision) && stored.revision >= 0 ? stored.revision : 0,
  };
}

function sdpMediaSections(description, type) {
  if (description?.type !== type || typeof description.sdp !== 'string' ||
      !description.sdp.startsWith('v=0') || description.sdp.length > 100000) return [];
  const sections = [];
  let sessionDirection = 'sendrecv';
  let current;
  for (const raw of description.sdp.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith('m=')) {
      const [kind, port] = line.slice(2).split(/\s+/);
      current = {kind, port: /^\d+(?:\/\d+)?$/.test(port || '') ? Number(port.split('/')[0]) : 0};
      sections.push(current);
    } else if (/^a=(sendrecv|sendonly|recvonly|inactive)$/.test(line)) {
      if (current) current.direction = line.slice(2);
      else sessionDirection = line.slice(2);
    } else if (current && line.startsWith('a=mid:')) {
      current.mid = line.slice(6);
    }
  }
  return sections.map(section => ({...section, direction: section.direction || sessionDirection}));
}

function hasNegotiatedVideo(call) {
  const offer = sdpMediaSections(call.offer, 'offer');
  const answer = sdpMediaSections(call.answer, 'answer');
  return offer.some((section, index) => {
    const accepted = answer[index];
    return section.kind === 'video' && accepted?.kind === 'video' &&
      section.port > 0 && section.port <= 65535 && accepted.port > 0 && accepted.port <= 65535 &&
      section.mid === accepted.mid && section.direction === 'sendrecv' && accepted.direction === 'sendrecv';
  });
}

function registerVideoCapability(call, uid, now, roomParticipants) {
  if (!Array.isArray(call?.participants) || !call.participants.includes(uid)) {
    throw new CallMediaError('permission-denied', 'Not a call participant.');
  }
  if (call.state !== 'accepted' || !(call.expiresAt > now)) {
    throw new CallMediaError('failed-precondition', 'Video is available only during an active call.');
  }
  if (!Array.isArray(roomParticipants) || !call.participants.every(id => roomParticipants.includes(id))) {
    throw new CallMediaError('permission-denied', 'This call is no longer available in your shared chat.');
  }
  // A new app can refresh its own capability after the signaling backend was
  // upgraded, but cannot grant that capability to an old/other client. Both
  // stored descriptions must already support sending and receiving video.
  if (!hasNegotiatedVideo(call)) {
    throw new CallMediaError('failed-precondition', 'This call was connected as voice-only. Start a new call with both apps updated to use video.');
  }
  return {...videoCapabilities(call), [uid]: true};
}

function updateMedia(call, uid, request, now, roomParticipants) {
  if (!Array.isArray(call?.participants) || !call.participants.includes(uid)) {
    throw new CallMediaError('permission-denied', 'Not a call participant.');
  }
  if (call.state !== 'accepted' || !(call.expiresAt > now)) {
    throw new CallMediaError('failed-precondition', 'Video is available only during an active call.');
  }
  if (typeof request.videoEnabled !== 'boolean' ||
      (request.mode !== undefined && !['voice', 'video'].includes(request.mode)) ||
      (request.mode === 'voice' && request.videoEnabled) ||
      (request.expectedRevision !== undefined && (!Number.isSafeInteger(request.expectedRevision) || request.expectedRevision < 0))) {
    throw new CallMediaError('invalid-argument', 'Invalid call media settings.');
  }
  const previous = currentMedia(call);
  const enablingVideo = request.videoEnabled;
  if (enablingVideo) {
    if (!Array.isArray(roomParticipants) || !call.participants.every(id => roomParticipants.includes(id))) {
      throw new CallMediaError('permission-denied', 'This call is no longer available in your shared chat.');
    }
    if (!call.participants.every(id => videoCapabilities(call)[id])) {
      throw new CallMediaError('failed-precondition', 'Both users must update MediCare to use video calling.');
    }
    // A camera permission prompt can remain open while the partner switches
    // back to voice. Do not publish that now-stale enable when it returns.
    if (request.expectedRevision !== undefined && request.expectedRevision !== previous.revision) {
      throw new CallMediaError('failed-precondition', 'Call media changed. Please try enabling your camera again.');
    }
  }
  const next = {...previous, cameras: {...previous.cameras}, revision: previous.revision + 1};
  if (request.mode === 'voice') {
    next.mode = 'voice';
    call.participants.forEach(id => { next.cameras[id] = false; });
  } else {
    if (request.videoEnabled) next.mode = 'video';
    next.cameras[uid] = request.videoEnabled;
  }
  return next;
}

module.exports = {CallMediaError, initialMedia, currentMedia, videoCapabilities, hasNegotiatedVideo, registerVideoCapability, updateMedia};
