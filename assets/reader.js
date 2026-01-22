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
    // New flag to track if we are at the very start of the book
    let isFirstChapter = false; 
    
    function setScroll(x) {
        globalScrollX = x;
        // Use transform for smooth movement (Checkpoint 5 Architecture)
        document.body.style.transform = `translate3d(${-x}px, 0, 0)`;
    }

    // --- 2. INIT ---
    function init() {
        const pages = Math.ceil(getScrollWidth() / getWidth());
        post(`page_count:${pages}`);

        const urlParams = new URLSearchParams(window.location.search);
        
        // 1. Check if this is the first chapter (Passed from Flutter)
        isFirstChapter = urlParams.get('isFirst') === 'true';

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

            // Force Repaint (Digital Nudge)
            const forceReflow = document.body.offsetHeight; 

            // Update Flutter
            const newPercent = targetX / total;
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

        // Tap
        if (Math.abs(diff) < 10) {
            post('toggle_controls');
            return;
        }

        // Snap Logic
        let targetPage = Math.round(globalScrollX / width);
        
        if (diff > 50) { // NEXT (Swipe Left)
            if (globalScrollX < maxScroll - 10) {
                targetPage = Math.ceil(startScroll / width) + 1;
            } else { 
                post('next_chapter'); 
                return; 
            }
        } 
        else if (diff < -50) { // PREV (Swipe Right)
            if (globalScrollX > 10) {
                // Normal internal page turn
                targetPage = Math.floor(startScroll / width) - 1;
            } else { 
                // We are at the start of the chapter
                
                // CRITICAL FIX: If first chapter, don't allow prev_chapter
                if (isFirstChapter) {
                    // Snap back to 0 (Rubber band effect)
                    targetPage = 0;
                } else {
                    post('prev_chapter'); 
                    return; 
                }
            }
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
                
                const total = getScrollWidth() - getWidth();
                // Avoid divide by zero
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