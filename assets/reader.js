(function() {

    // --- 1. SETUP ---
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
    function W()  { return document.documentElement.clientWidth || window.innerWidth; }
    function SW() { return document.body.scrollWidth; }

    // Set GPU hints directly on body via JS (guaranteed before first touch)
    var s = document.body.style;
    s.height               = (window.innerHeight - 80) + 'px';
    s.width                = '100vw';
    s.margin               = '40px 0';
    s.padding              = '0';
    s.columnWidth          = '100vw';
    s.columnGap            = '0';
    s.columnFill           = 'auto';
    s.willChange           = 'transform';
    s.webkitBackfaceVisibility = 'hidden';
    s.backfaceVisibility   = 'hidden';
    s.overflow             = 'visible';

    document.documentElement.style.overflow = 'hidden';
    document.documentElement.style.height   = '100vh';
    document.documentElement.style.width    = '100vw';

    var curX = 0;
    function setX(x) {
        curX = x;
        document.body.style.transform = 'translate3d(' + (-x) + 'px, 0, 0)';
        window.globalScrollX = x;
    }
    window.globalScrollX = 0;

    window.setTheme = function(isDark) {
        var fn = isDark ? 'add' : 'remove';
        document.documentElement.classList[fn]('dark-mode');
        document.body.classList[fn]('dark-mode');
    };

    // --- 2. IMAGE FIXER ---
    function fixImages() {
        var token  = window.AUTH_TOKEN || '';
        var imgs   = document.getElementsByTagName('img');
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
    window.fixImages = fixImages;

    // --- 3. INIT ---
    function init() {
        dragging = false;

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

    // --- 5. TOUCH ENGINE ---
    var startX    = 0;
    var startY    = 0;
    var startPage = 0;
    var dragging  = false;

    window.addEventListener('touchstart', function(e) {
        startX    = e.touches[0].clientX;
        startY    = e.touches[0].clientY;
        startPage = Math.round(curX / W());
        dragging  = true;
        window._snapCancel = true;
    }, { passive: true });

    window.addEventListener('touchmove', function(e) {
        if (!dragging) return;
        var diff    = startX - e.touches[0].clientX;
        var targetX = startPage * W() + diff;
        setX(Math.max(-W(), Math.min(SW(), targetX)));
    }, { passive: true });

    function onTouchEnd(e) {
        if (!dragging) return;
        dragging = false;

        var w       = W();
        var touch   = e.changedTouches ? e.changedTouches[0] : e.touches[0];
        var clientX = touch ? touch.clientX : startX;
        var clientY = touch ? touch.clientY : startY;
        var diffX   = startX - clientX;
        var diffY   = startY - clientY;

        if (Math.abs(diffX) < 10 && Math.abs(diffY) < 10) {
            post('toggle_controls');
            var validP = Math.max(0, Math.min(Math.ceil((SW()-20)/w)-1, startPage));
            snapTo(validP * w);
            return;
        }

        var maxX = SW() - w;

        if (curX < -w * 0.15) {
            var params = new URLSearchParams(window.location.search);
            if (params.get('isFirst') !== 'true') {
                snapTo(-w);
                setTimeout(function() { post('prev_chapter'); }, 250);
                return;
            }
        }
        if (curX > maxX + w * 0.15) {
            snapTo(SW());
            setTimeout(function() { post('next_chapter'); }, 250);
            return;
        }

        var targetPage = startPage;
        if (diffX > 50)       targetPage = startPage + 1;
        else if (diffX < -50) targetPage = startPage - 1;

        var maxPage = Math.ceil((SW() - 20) / w) - 1;
        targetPage  = Math.max(0, Math.min(maxPage, targetPage));
        snapTo(targetPage * w);
    }

    window.addEventListener('touchend',   onTouchEnd, { passive: true });
    window.addEventListener('touchcancel', onTouchEnd, { passive: true });

    // --- 6. SNAP ANIMATION ---
    function snapTo(targetX) {
        window._snapCancel = false;
        var from = curX;
        var dist = targetX - from;
        if (Math.abs(dist) < 1) { setX(targetX); reportProgress(targetX); return; }

        var startTime = null;
        function step(ts) {
            if (window._snapCancel) return;
            if (!startTime) startTime = ts;
            var p    = Math.min((ts - startTime) / 250, 1);
            var ease = 1 - Math.pow(1 - p, 3);
            setX(from + dist * ease);
            if (p < 1) requestAnimationFrame(step);
            else { setX(targetX); reportProgress(targetX); }
        }
        requestAnimationFrame(step);
    }

    function reportProgress(x) {
        var total  = SW() - W();
        var validX = Math.max(0, Math.min(total, x));
        post('progress:' + (total > 0 ? validX / total : 0));
    }

    init();
})();