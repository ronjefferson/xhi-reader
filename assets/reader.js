(function() {
    function checkInitialPosition() {
        const urlParams = new URLSearchParams(window.location.search);
        if (urlParams.get('pos') === 'end') {
            document.body.scrollLeft = document.body.scrollWidth;
        } else {
            document.body.scrollLeft = 0;
        }
    }
    if (document.body) checkInitialPosition();
    window.onload = checkInitialPosition;

    let startX = 0;
    let startTime = 0;
    let isSwiping = false;

    // Listen on WINDOW to catch events that pass through the text
    window.addEventListener('touchstart', (e) => {
        startX = e.changedTouches[0].screenX;
        startTime = new Date().getTime();
        isSwiping = false;
    }, { passive: false });

    window.addEventListener('touchmove', (e) => {
        isSwiping = true;
    }, { passive: false });

    window.addEventListener('touchend', (e) => {
        const timeDiff = new Date().getTime() - startTime;
        const diffX = startX - e.changedTouches[0].screenX;

        // TAP DETECTION
        if (!isSwiping && timeDiff < 300) {
            // Because pointer-events: none is on text, we don't need complex logic.
            // The text is invisible to the tap, so no focus jump occurs.
            if (window.PrintReader) window.PrintReader.postMessage('toggle_controls');
            return;
        }

        // SWIPE NAVIGATION
        if (Math.abs(diffX) > 50) {
            const total = document.body.scrollWidth; 
            const view = window.innerWidth;
            const max = total - view;
            const current = document.body.scrollLeft;
            
            const atStart = current <= 20; 
            const atEnd = current >= (max - 20);

            if (diffX > 50 && atEnd) {
                animate('next');
            } else if (diffX < -50 && atStart) {
                animate('prev');
            }
        }
    }, { passive: false });

    function animate(dir) {
        document.body.style.transition = "transform 0.2s ease-out";
        if (dir === 'next') {
            document.body.style.transform = "translateX(-100vw)";
            setTimeout(() => { if(window.PrintReader) window.PrintReader.postMessage('next_chapter'); }, 200);
        } else {
            document.body.style.transform = "translateX(100vw)";
            setTimeout(() => { if(window.PrintReader) window.PrintReader.postMessage('prev_chapter'); }, 200);
        }
    }
})();