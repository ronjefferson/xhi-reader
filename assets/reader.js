(function() {
    // --- 1. SETUP & UTILS ---
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
    function getWidth() { return document.documentElement.clientWidth || window.innerWidth; }
    function getScrollWidth() { return document.body.scrollWidth; }

    window.setTheme = function(isDark) {
        if (isDark) {
            document.documentElement.classList.add('dark-mode');
            document.body.classList.add('dark-mode');
        } else {
            document.documentElement.classList.remove('dark-mode');
            document.body.classList.remove('dark-mode');
        }
    }

    function setScroll(x) {
        // Use transform for high-performance smooth scrolling
        document.body.style.transform = 'translate3d(' + (-x) + 'px, 0, 0)';
        window.globalScrollX = x;
    }
    window.globalScrollX = 0; // Track position in JS

    // --- 2. IMAGE FIXER (CRITICAL FOR ONLINE & EMULATOR) ---
    function fixImages() {
        let token = window.AUTH_TOKEN || ''; 
        let imgs = document.getElementsByTagName('img');
        
        for(let i=0; i<imgs.length; i++) {
            let src = imgs[i].src;
            let originalSrc = src;

            // A. Fix Emulator IP (Localhost -> 10.0.2.2)
            if (src.includes('localhost') || src.includes('127.0.0.1')) {
                src = src.replace('localhost', '10.0.2.2').replace('127.0.0.1', '10.0.2.2');
            }
            
            // B. Fix Capitalization (The 404 Error Fix)
            if (src.includes('/Images/')) {
                src = src.replace('/Images/', '/images/');
            }

            // C. Append Auth Token (If Online)
            if (token && !src.includes('token=')) {
                let separator = src.includes('?') ? '&' : '?';
                src = src + separator + 'token=' + token;
            }
            
            // D. Apply Changes
            if (src !== originalSrc) imgs[i].src = src;
        }
    }

    // --- 3. INITIALIZATION ---
    function init() {
        // Run Image Fixer immediately, then retry in case DOM is slow
        fixImages();
        setTimeout(fixImages, 500);
        setTimeout(fixImages, 1500);

        const w = getWidth();
        const params = new URLSearchParams(window.location.search);
        
        // Restore Position
        if (params.get('pos') === 'end') {
            setScroll(getScrollWidth() - w);
        } else {
            setScroll(0);
        }

        // Notify Flutter we are ready
        setTimeout(function(){ post('ready'); }, 100);
    }

    // --- 4. SLIDER JUMP ---
    window.scrollToPercent = function(percent) {
        const w = getWidth();
        const total = getScrollWidth() - w;
        const targetX = Math.round((total * percent) / w) * w; // Snap to nearest page
        setScroll(targetX);
    };

    // --- 5. TOUCH & GESTURE ENGINE ---
    let startX = 0; 
    let startY = 0;
    let isDragging = false;
    let startPage = 0; 

    window.addEventListener('touchstart', function(e) {
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        isDragging = true;
        
        const w = getWidth();
        // GHOST PAGE FIX: Subtract 20px buffer
        const maxPage = Math.ceil((getScrollWidth() - 20) / w) - 1;
        
        // Calculate current page
        let rawStart = Math.round((window.globalScrollX || 0) / w);
        
        // Clamp (Prevent looping/crashing on resize)
        if (rawStart > maxPage) rawStart = maxPage;
        if (rawStart < 0) rawStart = 0;
        
        startPage = rawStart;
    }, {passive: false});

    window.addEventListener('touchmove', function(e) {
        if (!isDragging) return;
        const diff = startX - e.touches[0].clientX;
        
        // Lock vertical scroll, allow horizontal
        if (Math.abs(diff) > 5 && e.cancelable) {
            e.preventDefault();
        }
        
        // follow finger (1:1 movement)
        setScroll((startPage * getWidth()) + diff);
    }, {passive: false});

    window.addEventListener('touchend', function(e) {
        if (!isDragging) return;
        isDragging = false;
        
        const w = getWidth();
        const diffX = startX - e.changedTouches[0].clientX;
        const diffY = startY - e.changedTouches[0].clientY;
        
        // --- TAP DETECTION ---
        // If moved less than 10px, it's a tap, not a swipe.
        if (Math.abs(diffX) < 10 && Math.abs(diffY) < 10) { 
            post('toggle_controls'); 
            // Snap back to perfect alignment just in case
            smoothScrollTo(startPage * w);
            return; 
        }

        // --- SWIPE LOGIC ---
        let targetPage = startPage;
        if (diffX > 50) targetPage = startPage + 1; // Next
        else if (diffX < -50) targetPage = startPage - 1; // Prev

        // Boundary Checks
        const maxPage = Math.ceil((getScrollWidth() - 20) / w) - 1;
        
        // Check for Chapter Change
        if (targetPage < 0) { 
            const params = new URLSearchParams(window.location.search);
            // Only go to prev chapter if NOT the first one
            if (params.get('isFirst') !== 'true') { post('prev_chapter'); return; }
            targetPage = 0; // Else bounce back
        }
        
        if (targetPage > maxPage) { post('next_chapter'); return; }

        // Animate to target
        const targetX = targetPage * w;
        smoothScrollTo(targetX);
    }, {passive: false});

    // --- 6. ANIMATION LOOP ---
    function smoothScrollTo(targetX) {
        const start = window.globalScrollX || 0;
        const dist = targetX - start;
        let startTime = null;
        
        function step(ts) {
            if (!startTime) startTime = ts;
            const p = Math.min((ts - startTime)/250, 1); // 250ms duration
            const ease = 1 - Math.pow(1 - p, 3); // Cubic ease-out
            
            setScroll(start + (dist * ease));
            
            if (p < 1) requestAnimationFrame(step);
            else {
                setScroll(targetX); // Ensure exact finish
                
                // Update Flutter Slider
                const total = getScrollWidth() - getWidth();
                const progress = total > 0 ? targetX/total : 0;
                post('progress:' + progress);
            }
        }
        requestAnimationFrame(step);
    }

    // Start
    init();
})();