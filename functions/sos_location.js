'use strict';

function validLocation(alert) {
  return alert.locationStatus === 'available' &&
    Number.isFinite(alert.latitude) && Math.abs(alert.latitude) <= 90 &&
    Number.isFinite(alert.longitude) && Math.abs(alert.longitude) <= 180;
}

function sosLocationFields(alert) {
  const available = validLocation(alert);
  const name = typeof alert.locationName === 'string' ? alert.locationName.trim() : '';
  const accuracy = Number.isFinite(alert.locationAccuracy) && alert.locationAccuracy >= 0 ? alert.locationAccuracy : null;
  const timestamp = Number.isFinite(alert.locationCapturedAt) && Number.isFinite(new Date(alert.locationCapturedAt).getTime())
    ? alert.locationCapturedAt : null;
  const coordinates = `${alert.latitude},${alert.longitude}`;
  let text;
  if (available) {
    text = `SOS! I need help. My GPS location: ${alert.latitude}, ${alert.longitude}.` +
      (name ? `\nNearby address (approx.): ${name}` : '') +
      `\nAccuracy: ±${accuracy === null ? '?' : Math.round(accuracy)} m. Captured: ${timestamp === null ? 'unknown' : new Date(timestamp).toISOString()}. This is a snapshot, not live tracking.`;
  } else if (alert.locationStatus === 'pending') {
    text = 'SOS! I need help. Acquiring my location…';
  } else {
    const reason = {
      services_disabled: 'Location/GPS is switched off on my phone.',
      permission_denied: 'Location permission was denied on my phone.',
      permission_denied_forever: 'Location access is blocked in my app settings.',
      timeout: 'My phone could not obtain a current GPS fix.',
    }[alert.locationFailure || alert.locationStatus] || 'My phone could not obtain its current location.';
    text = `SOS! I need help. ${reason} Please contact me.`;
  }
  return {
    text,
    mapUrl: available ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(coordinates)}` : '',
    locationStatus: available ? 'available' : ['pending', 'permission_denied', 'services_disabled', 'unavailable'].includes(alert.locationStatus) ? alert.locationStatus : 'unavailable',
    // Explicit nulls remove a previous point if a merged event loses location.
    latitude: available ? alert.latitude : null,
    longitude: available ? alert.longitude : null,
    locationName: available ? name : '',
    locationAccuracy: available ? accuracy : null,
    locationCapturedAt: available ? timestamp : null,
  };
}

module.exports = {validLocation, sosLocationFields};
