// Injected at document start inside the iOS app only. Replaces navigator.geolocation with one that gets
// its positions from CoreLocation through the native gpsBridge handler (see GPSBridge.swift).
// In a normal browser the handler does not exist and navigator.geolocation is left untouched.
(() => {
  const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.gpsBridge;
  if (!bridge) return;

  const PERMISSION_DENIED = 1, POSITION_UNAVAILABLE = 2, TIMEOUT = 3;
  const subscribers = new Map();   // id -> { success, error, options, once, timer }
  let nextId = 1;
  let last = null;                  // last position from native, for maximumAge
  let running = null;               // null when stopped, otherwise whether native runs in high accuracy

  function makePosition(p) {
    return {
      coords: {
        latitude: p.lat, longitude: p.lng, accuracy: p.acc,
        altitude: null, altitudeAccuracy: null, heading: null, speed: null
      },
      timestamp: p.t
    };
  }

  function makeError(code, message) {
    return { code, message: message || '', PERMISSION_DENIED, POSITION_UNAVAILABLE, TIMEOUT };
  }

  // Starts, stops or changes the accuracy of the native updates so they match the current subscribers.
  function syncNative() {
    if (!subscribers.size) {
      if (running !== null) bridge.postMessage({ type: 'stop' });
      running = null;
      return;
    }
    const high = [...subscribers.values()].some(s => s.options.enableHighAccuracy);
    if (running !== high) bridge.postMessage({ type: 'start', highAccuracy: high });
    running = high;
  }

  // The timeout counts from the request, and for a watch again from each position.
  function armTimeout(id) {
    const s = subscribers.get(id);
    if (!s) return;
    clearTimeout(s.timer);
    const timeout = s.options.timeout;
    if (!(timeout >= 0) || timeout === Infinity) return;
    s.timer = setTimeout(() => {
      if (!subscribers.has(id)) return;
      if (s.once) remove(id);
      else armTimeout(id);
      if (s.error) s.error(makeError(TIMEOUT, 'Timeout expired'));
    }, timeout);
  }

  function remove(id) {
    const s = subscribers.get(id);
    if (!s) return;
    clearTimeout(s.timer);
    subscribers.delete(id);
    syncNative();
  }

  function subscribe(success, error, options, once) {
    const id = nextId++;
    const s = { success, error, options: options || {}, once, timer: null };
    subscribers.set(id, s);
    const maxAge = Number(s.options.maximumAge) || 0;
    if (last && maxAge > 0 && Date.now() - last.t <= maxAge) {
      // A cached position is recent enough: answer straight away, like the browser does.
      setTimeout(() => {
        if (!subscribers.has(id)) return;
        if (once) remove(id);
        success(makePosition(last));
      }, 0);
      if (once) return id;
    }
    armTimeout(id);
    syncNative();
    return id;
  }

  // Called by GPSBridge.swift.
  window.__gpsBridge = {
    location(p) {
      last = p;
      for (const [id, s] of [...subscribers]) {
        if (s.once) remove(id);
        else armTimeout(id);
        s.success(makePosition(p));
      }
    },
    error(code, message) {
      for (const [id, s] of [...subscribers]) {
        // Denied access ends every request, as in the browser. Other errors keep a watch going.
        if (s.once || code === PERMISSION_DENIED) remove(id);
        if (s.error) s.error(makeError(code, message));
      }
    }
  };

  const geolocation = {
    getCurrentPosition(success, error, options) { subscribe(success, error, options, true); },
    watchPosition(success, error, options) { return subscribe(success, error, options, false); },
    clearWatch(id) { remove(id); }
  };
  Object.defineProperty(navigator, 'geolocation', { value: geolocation, configurable: true });
})();
