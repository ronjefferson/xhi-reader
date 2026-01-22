(function() {
    // --- UTILS ---
    // We track scroll manually via Transform
    let globalScrollX = 0; 

    function getScrollWidth() { 
        return document.body.scrollWidth || document.documentElement.scrollWidth; 
    }
    
    function getViewportWidth() { return window.innerWidth; }
    
    function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }

    // --- 1. CORE MOVEMENT ---
    function setScroll(x) {
        globalScrollX = x;
        document.body.style.transform = `translate3d(${-x}px, 0, 0)`;
    }

    // --- 2. INITIALIZATION ---
    let isFirstChapter = false;
    let isLastChapter = false;

    function checkInitialPosition() {
        const urlParams = new URLSearchParams(window.location.search);
        
        // READ FLAGS FROM FLUTTER
        isFirstChapter = urlParams.get('isFirst') === 'true';
        isLastChapter = urlParams.get('isLast') === 'true';

        if (urlParams.get('pos') === 'end') {
            const w = getScrollWidth() - getViewportWidth();
            setScroll(w);
        } else {
            setScroll(0);
        }
        setTimeout(() => { post('ready'); reportProgress(); }, 150);
    }
    window.onload = checkInitialPosition;

    // --- 3. REPORT PROGRESS ---
    function reportProgress() {
        const w = getViewportWidth();
        if (w <= 0) return;
        const total = getScrollWidth() - w;
        if (total <= 0) { post('progress:0.0'); return; }
        const p = globalScrollX / total;
        post(`progress:${Math.max(0, Math.min(1, p)).toFixed(4)}`);
    }
    window.addEventListener('resize', reportProgress);

    // --- 4. SLIDER JUMP ---
    window.scrollToPercent = function(percent) {
        const total = getScrollWidth() - getViewportWidth();
        if (total <= 0) return;
        setScroll(total * percent);
        reportProgress();
    };

    // --- 5. PHYSICS ENGINE ---
    let startX = 0;
    let startScroll = 0;
    let isDragging = false;
    let startTime = 0;
    let animationFrameId;

    window.addEventListener('touchstart', (e) => {
        cancelAnimationFrame(animationFrameId);
        startX = e.touches[0].clientX;
        startScroll = globalScrollX;
        startTime = new Date().getTime();
        isDragging = true;
    }, { passive: false });

    window.addEventListener('touchmove', (e) => {
        if (!isDragging) return;
        if (e.cancelable) e.preventDefault(); 
        
        const currentX = e.touches[0].clientX;
        const delta = startX - currentX; // +ve = Moving Right (Next)
        const intended = startScroll + delta;
        const width = getViewportWidth();
        const maxScroll = getScrollWidth() - width;

        // --- BLOCKING LOGIC ---

        // A. PULLING PREVIOUS (Moving Left into Void)
        if (intended < 0) {
            // STOP! If this is the first chapter, do not allow pull
            if (isFirstChapter) { 
                setScroll(0); 
                return; 
            }
            setScroll(intended); 
        } 
        // B. PULLING NEXT (Moving Right into Void)
        else if (intended > maxScroll) {
            // STOP! If this is the last chapter, do not allow pull
            if (isLastChapter) { 
                setScroll(maxScroll); 
                return; 
            }
            setScroll(intended);
        } 
        // C. NORMAL SCROLL
        else {
            setScroll(intended); 
        }
    }, { passive: false });

    window.addEventListener('touchend', (e) => {
        if (!isDragging) return;
        isDragging = false;

        const time = new Date().getTime() - startTime;
        const width = getViewportWidth();
        
        // TAP
        if (time < 300 && Math.abs(startX - e.changedTouches[0].clientX) < 10) {
            if (globalScrollX >= 0 && globalScrollX <= (getScrollWidth() - width)) {
                post('toggle_controls');
                return;
            }
        }

        // EDGE PULL SNAP
        const maxScroll = getScrollWidth() - width;
        const threshold = 60;

        // Pulling Previous
        if (globalScrollX < 0) {
            if (globalScrollX < -threshold && !isFirstChapter) {
                 smoothScrollTo(-width, () => post('prev_chapter'));
            } else {
                 smoothScrollTo(0);
            }
            return;
        }

        // Pulling Next
        if (globalScrollX > maxScroll) {
            const overflow = globalScrollX - maxScroll;
            if (overflow > threshold && !isLastChapter) {
                smoothScrollTo(maxScroll + width, () => post('next_chapter'));
            } else {
                smoothScrollTo(maxScroll);
            }
            return;
        }

        // NORMAL PAGE SNAP
        const endX = e.changedTouches[0].clientX;
        const diff = startX - endX;
        let startPage = Math.round(startScroll / width);
        let targetPage = startPage;
        const snapThreshold = 50;

        if (diff > snapThreshold) targetPage = startPage + 1;
        else if (diff < -snapThreshold) targetPage = startPage - 1;

        smoothScrollTo(targetPage * width);
        
    }, { passive: false });

    // --- ANIMATOR ---
    function smoothScrollTo(targetX, onFinish) {
        const startX = globalScrollX;
        const distance = targetX - startX;
        const duration = 250;
        let start = null;

        function step(timestamp) {
            if (!start) start = timestamp;
            const progress = timestamp - start;
            const percent = Math.min(progress / duration, 1);
            const ease = 1 - Math.pow(1 - percent, 3);
            
            setScroll(startX + (distance * ease));

            if (progress < duration) {
                animationFrameId = requestAnimationFrame(step);
            } else {
                reportProgress();
                if (onFinish) onFinish();
            }
        }
        animationFrameId = requestAnimationFrame(step);
    }
})();