(function() {

    // --- 1. SETUP ---
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
    function W()  { return document.documentElement.clientWidth || window.innerWidth; }
    function SW() { return pw.scrollWidth; }

    var pw = document.getElementById('pw');
    if (!pw) {
        pw = document.createElement('div');
        pw.id = 'pw';
        while (document.body.firstChild) pw.appendChild(document.body.firstChild);
        document.body.appendChild(pw);
        pw.style.cssText = [
            'display:block',
            'width:100vw',
            'height:100%',
            'column-width:100vw',
            'column-gap:0',
            'column-fill:auto',
            'will-change:transform',
            '-webkit-backface-visibility:hidden',
            'backface-visibility:hidden',
            'transform:translate3d(0,0,0)',
        ].join(';');
    }

    var curX = 0;
    function setX(x) {
        curX = x;
        pw.style.transform = 'translate3d(' + (-x) + 'px,0,0)';
    }

    Object.defineProperty(window, 'globalScrollX', {
        get: function() { return curX; },
        set: function(v) { curX = v; }
    });

    window.setTheme = function(isDark) {
        var fn = isDark ? 'add' : 'remove';
        document.documentElement.classList[fn]('dark-mode');
        document.body.classList[fn]('dark-mode');
        pw.classList[fn]('dark-mode');
    };

    // --- 2. IMAGE FIXER ---
    function fixImages() {
        var token = window.AUTH_TOKEN || '';
        var imgs  = pw.getElementsByTagName('img');
        
        // 🟢 FIX: Only replace localhost if NOT using file:// protocol
        var isOnline = window.location.protocol !== 'file:';

        for (var i = 0; i < imgs.length; i++) {
            var s = imgs[i].src, orig = s;
            
            if (isOnline) {
                if (s.indexOf('localhost') > -1 || s.indexOf('127.0.0.1') > -1)
                    s = s.replace('localhost', '10.0.2.2').replace('127.0.0.1', '10.0.2.2');
                
                if (s.indexOf('/Images/') > -1)
                    s = s.replace('/Images/', '/images/');
                
                if (token && s.indexOf('token=') === -1)
                    s += (s.indexOf('?') > -1 ? '&' : '?') + 'token=' + token;
            }
            
            if (s !== orig) imgs[i].src = s;
        }
    }
    
    // 🟢 EXPOSE FOR FLUTTER
    window.fixImages = fixImages;

    // --- 3. INIT ---
    function init() {
        // Reset states
        dragging = false;
        moved = false;
        window._snapCancel = true;

        var _ = document.body.offsetWidth; 
        
        fixImages();
        setTimeout(fixImages, 500);

        var params = new URLSearchParams(window.location.search);
        if (params.get('pos') === 'end') setX(SW() - W());
        else setX(0);

        setTimeout(function() { post('ready'); }, 100);
    }

    // --- 4. SLIDER JUMP ---
    window.scrollToPercent = function(percent) {
        var w      = W();
        var total  = SW() - w;
        var target = Math.round((total * percent) / w) * w;
        setX(target);
    };

    // --- 5. TOUCH ENGINE (GLOBAL LISTENERS) ---
    var startX    = 0;
    var startY    = 0;
    var startPage = 0;
    var dragging  = false;
    var moved     = false;

    // 🟢 LISTEN ON WINDOW (Fixes dead zones on partial pages)
    window.addEventListener('touchstart', function(e) {
        startX    = e.touches[0].clientX;
        startY    = e.touches[0].clientY;
        dragging  = true;
        moved     = false;
        window._snapCancel = true; 

        var w      = W();
        var raw    = Math.round(curX / w);
        startPage  = raw; 
    }, { passive: true });

    window.addEventListener('touchmove', function(e) {
        if (!dragging) return;
        moved     = true;
        var diff  = startX - e.touches[0].clientX;
        var targetX = startPage * W() + diff;
        setX(Math.max(-W(), Math.min(SW(), targetX))); 
    }, { passive: true });

    function onTouchEnd(e) {
        if (!dragging) return;
        dragging = false;

        var touch = e.changedTouches ? e.changedTouches[0] : e.touches[0];
        var clientX = touch ? touch.clientX : startX;
        var clientY = touch ? touch.clientY : startY;

        var w     = W();
        var diffX = startX - clientX;
        var diffY = startY - clientY;

        // TAP DETECTION
        if (!moved || (Math.abs(diffX) < 10 && Math.abs(diffY) < 10)) {
            post('toggle_controls');
            var validPage = Math.max(0, Math.min(Math.ceil((SW()-20)/w)-1, startPage));
            snapTo(validPage * w);
            return;
        }

        var maxX = SW() - w;

        // PREV CHAPTER
        if (curX < -w * 0.15) {
            var params = new URLSearchParams(window.location.search);
            if (params.get('isFirst') !== 'true') { 
                snapTo(-w); 
                setTimeout(function(){ post('prev_chapter'); }, 300);
                return; 
            }
        }

        // NEXT CHAPTER
        if (curX > maxX + w * 0.15) {
             snapTo(SW()); 
             setTimeout(function(){ post('next_chapter'); }, 300);
             return;
        }

        // 15% THRESHOLD SNAP
        var threshold = w * 0.15; 
        var targetPage = startPage;

        if (diffX > threshold) targetPage = startPage + 1;
        else if (diffX < -threshold) targetPage = startPage - 1;

        var maxPage  = Math.ceil((SW() - 20) / w) - 1;
        targetPage   = Math.max(0, Math.min(maxPage, targetPage));
        
        snapTo(targetPage * w);
    }

    window.addEventListener('touchend', onTouchEnd, { passive: true });
    window.addEventListener('touchcancel', onTouchEnd, { passive: true });

    // --- 6. SNAP ---
    function snapTo(targetX) {
        window._snapCancel = false;
        var from  = curX;
        var dist  = targetX - from;
        if (Math.abs(dist) < 1) { setX(targetX); reportProgress(targetX); return; }

        var dur   = Math.min(600, Math.abs(dist) * 0.8);
        var t0    = null;

        function step(ts) {
            if (window._snapCancel) return;
            if (!t0) t0 = ts;
            var t    = Math.min((ts - t0) / dur, 1);
            var ease = 1 - Math.pow(1 - t, 3);
            setX(from + dist * ease);
            if (t < 1) requestAnimationFrame(step);
            else { setX(targetX); reportProgress(targetX); }
        }
        requestAnimationFrame(step);
    }

    function reportProgress(x) {
        var total = SW() - W();
        var validX = Math.max(0, Math.min(total, x));
        post('progress:' + (total > 0 ? validX / total : 0));
    }

    init();
})();