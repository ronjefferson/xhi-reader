(function() {
    // --- UTILS ---
    function getScrollX() { return window.pageXOffset || document.documentElement.scrollLeft || document.body.scrollLeft || 0; }
    function getScrollWidth() { return document.documentElement.scrollWidth || document.body.scrollWidth || 0; }
    function getViewportWidth() { return window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth || 0; }
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }

    // --- 1. INITIALIZATION ---
    function checkInitialPosition() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('pos') === 'end') {
            const w = getScrollWidth();
            window.scrollTo(w, 0); 
        } else {
            window.scrollTo(0, 0); 
        }
        setTimeout(() => { post('ready'); reportProgress(); }, 150);
    }
    if (document.body) checkInitialPosition();
    window.onload = checkInitialPosition;

    // --- 2. REPORT PROGRESS ---
    function reportProgress() {
        const w = getViewportWidth();
        if (w <= 0) return;
        const total = getScrollWidth() - w;
        if (total <= 0) { post('progress:0.0'); return; }
        const p = getScrollX() / total;
        post(`progress:${Math.max(0, Math.min(1, p)).toFixed(4)}`);
    }
    window.addEventListener('resize', reportProgress);

    // --- 3. SLIDER JUMP ---
    window.scrollToPercent = function(percent) {
        const total = getScrollWidth() - getViewportWidth();
        if (total <= 0) return;
        window.scrollTo({ left: total * percent, behavior: 'auto' });
        reportProgress();
    };

    // --- 4. PHYSICS ENGINE (1:1 Finger Tracking) ---
    let startX = 0;
    let startScroll = 0;
    let isDragging = false;
    let startTime = 0;
    let animationFrameId;

    // A. TOUCH START
    window.addEventListener('touchstart', (e) => {
        cancelAnimationFrame(animationFrameId); // Stop any active snap
        startX = e.touches[0].clientX;
        startScroll = getScrollX();
        startTime = new Date().getTime();
        isDragging = true;
    }, { passive: false });

    // B. TOUCH MOVE (Sticky Scroll)
    window.addEventListener('touchmove', (e) => {
        if (!isDragging) return;
        if (e.cancelable) e.preventDefault(); // Stop native scroll momentum
        
        const currentX = e.touches[0].clientX;
        const diff = startX - currentX;
        
        // Move page exactly with finger
        window.scrollTo(startScroll + diff, 0);
        
    }, { passive: false });

    // C. TOUCH END (Snap)
    window.addEventListener('touchend', (e) => {
        if (!isDragging) return;
        isDragging = false;

        const endX = e.changedTouches[0].clientX;
        const diff = startX - endX;
        const time = new Date().getTime() - startTime;
        const width = getViewportWidth();
        
        // 1. TAP DETECTION
        if (time < 300 && Math.abs(diff) < 10) {
            post('toggle_controls');
            return;
        }

        // 2. CALCULATE TARGET PAGE
        // We use the START position as the anchor
        let startPage = Math.round(startScroll / width);
        let targetPage = startPage;
        
        const currentScroll = getScrollX();
        const maxScroll = getScrollWidth() - width;
        const threshold = 50; // Drag 50px to commit turn

        // NEXT PAGE
        if (diff > threshold) {
            if (startScroll >= maxScroll - 10) { post('next_chapter'); return; }
            targetPage = startPage + 1;
        } 
        // PREV PAGE
        else if (diff < -threshold) {
            if (startScroll <= 10) { post('prev_chapter'); return; }
            targetPage = startPage - 1;
        }
        
        // 3. EXECUTE SNAP
        smoothScrollTo(targetPage * width);
        
    }, { passive: false });

    // Custom Animation for "Tight" Snap Feel
    function smoothScrollTo(targetX) {
        const startX = getScrollX();
        const distance = targetX - startX;
        const duration = 250; // Fast snap (250ms)
        let start = null;

        function step(timestamp) {
            if (!start) start = timestamp;
            const progress = timestamp - start;
            const percent = Math.min(progress / duration, 1);
            
            // Ease Out Cubic (Starts fast, slows down gently)
            const ease = 1 - Math.pow(1 - percent, 3);
            
            window.scrollTo(startX + (distance * ease), 0);

            if (progress < duration) {
                animationFrameId = requestAnimationFrame(step);
            } else {
                reportProgress();
            }
        }
        animationFrameId = requestAnimationFrame(step);
    }
})();