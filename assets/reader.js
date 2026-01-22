(function() {
    // --- 1. SETUP ---
    window.setTheme = function(isDark) {
        if (isDark) {
            document.documentElement.classList.add('dark-mode');
            document.body.classList.add('dark-mode');
        } else {
            document.documentElement.classList.remove('dark-mode');
            document.body.classList.remove('dark-mode');
        }
    }

    function getWidth() { return window.innerWidth; }
    function getScrollWidth() { return document.body.scrollWidth; }
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }

    let globalScrollX = 0;
    
    function setScroll(x) {
        globalScrollX = x;
        document.body.style.transform = `translate3d(${-x}px, 0, 0)`;
    }

    // --- 2. INIT ---
    function init() {
        const pages = Math.ceil(getScrollWidth() / getWidth());
        post(`page_count:${pages}`);

        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('pos') === 'end') {
            setScroll(getScrollWidth() - getWidth());
        } else {
            setScroll(0);
        }
        
        setTimeout(() => post('ready'), 100);
    }

    // --- 3. SLIDER JUMP ---
    window.scrollToPercent = function(percent) {
        requestAnimationFrame(() => {
            const width = getWidth();
            const total = getScrollWidth() - width;
            if (total <= 0) return;

            const rawTarget = total * percent;
            const pageIndex = Math.round(rawTarget / width);
            const targetX = pageIndex * width;

            setScroll(targetX);

            // Force Repaint
            const forceReflow = document.body.offsetHeight; 

            // Update Flutter (Safe Calculation)
            const newPercent = total > 0 ? targetX / total : 0;
            post(`progress:${newPercent}`);
        });
    };

    // --- 4. PHYSICS ENGINE ---
    let startX = 0;
    let startScroll = 0;
    let isDragging = false;

    window.addEventListener('touchstart', (e) => {
        startX = e.touches[0].clientX;
        startScroll = globalScrollX;
        isDragging = true;
    }, { passive: false });

    window.addEventListener('touchmove', (e) => {
        if (!isDragging) return;
        const currentX = e.touches[0].clientX;
        const delta = startX - currentX;
        setScroll(startScroll + delta);
    }, { passive: false });

    window.addEventListener('touchend', (e) => {
        if (!isDragging) return;
        isDragging = false;

        const width = getWidth();
        const maxScroll = getScrollWidth() - width;
        const diff = startX - e.changedTouches[0].clientX;

        if (Math.abs(diff) < 10) {
            post('toggle_controls');
            return;
        }

        let targetPage = Math.round(globalScrollX / width);
        
        if (diff > 50) { 
            if (globalScrollX < maxScroll - 10) targetPage = Math.ceil(startScroll / width) + 1;
            else { post('next_chapter'); return; }
        } else if (diff < -50) { 
            if (globalScrollX > 10) targetPage = Math.floor(startScroll / width) - 1;
            else { post('prev_chapter'); return; }
        }

        const targetX = targetPage * width;
        smoothScrollTo(targetX);
    }, { passive: false });

    function smoothScrollTo(targetX) {
        const start = globalScrollX;
        const dist = targetX - start;
        const duration = 200;
        let startTime = null;

        function step(timestamp) {
            if (!startTime) startTime = timestamp;
            const progress = timestamp - startTime;
            const percent = Math.min(progress / duration, 1);
            const ease = 1 - Math.pow(1 - percent, 3);
            
            setScroll(start + (dist * ease));

            if (progress < duration) {
                requestAnimationFrame(step);
            } else {
                setScroll(targetX);
                
                // CRASH FIX: Check for 0 width to avoid Infinity
                const total = getScrollWidth() - getWidth();
                const p = total > 0 ? targetX / total : 0;
                post(`progress:${p}`);
            }
        }
        requestAnimationFrame(step);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();