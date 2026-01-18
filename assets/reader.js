(function() {
    function checkReady() {
        if (document.body) {
            initializeReader();
        } else {
            setTimeout(checkReady, 10);
        }
    }
    checkReady();

    function initializeReader() {
        // --- VISIBLE DEBUGGER ---
        const debug = document.createElement('div');
        debug.style.cssText = "position:fixed; bottom:10px; left:10px; background:rgba(0,0,0,0.8); color:#00ff00; padding:8px; z-index:9999; font-size:14px; font-family:monospace; pointer-events:none; border-radius:4px;";
        document.body.appendChild(debug);

        // HELPER: Get the REAL scroll position
        // Since we scroll the BODY, we must read body.scrollLeft, NOT window.scrollX
        function getScrollPos() {
            return Math.ceil(document.body.scrollLeft);
        }

        function updateDebug() {
            if (!document.body) return;
            
            const current = getScrollPos();
            const totalWidth = document.body.scrollWidth;
            const screenW = window.innerWidth;
            const max = Math.round(totalWidth - screenW);
            
            // Calculate Page Count
            const pages = Math.round(totalWidth / screenW);
            
            const atStart = current <= 5;
            const atEnd = current >= (max - 20);
            
            debug.innerText = `Pg:${pages} | Pos:${current}/${max} | End:${atEnd}`;
        }

        // LISTEN EVERYWHERE (Use Capture to force detection)
        window.addEventListener('scroll', updateDebug, true);
        document.body.addEventListener('scroll', updateDebug, true);
        window.addEventListener('resize', updateDebug);
        setTimeout(updateDebug, 500); 

        // --- SWIPE LOGIC ---
        let startX = 0;
        let startScrollPos = 0;
        let isAnimating = false;

        document.addEventListener('touchstart', (e) => {
            startX = e.changedTouches[0].screenX;
            // Capture Start Position from BODY
            startScrollPos = getScrollPos();
        }, { passive: true });

        document.addEventListener('touchend', (e) => {
            if (isAnimating) return;

            const endX = e.changedTouches[0].screenX;
            const diff = startX - endX;
            
            const maxScroll = Math.round(document.body.scrollWidth - window.innerWidth);
            
            // Logic Gates
            const startedAtStart = startScrollPos <= 5;
            const startedAtEnd = startScrollPos >= (maxScroll - 20);

            // NEXT CHAPTER
            if (diff > 50 && startedAtEnd) {
                animateAndExit('next');
            }
            
            // PREV CHAPTER
            else if (diff < -50 && startedAtStart) {
                animateAndExit('prev');
            }
        });

        function animateAndExit(direction) {
            isAnimating = true;
            if (direction === 'next') {
                document.body.style.transform = "translateX(-100vw)";
                document.body.style.opacity = "0";
                setTimeout(() => { if (window.PrintReader) window.PrintReader.postMessage('next_chapter'); }, 300);
            } else {
                document.body.style.transform = "translateX(100vw)";
                document.body.style.opacity = "0";
                setTimeout(() => { if (window.PrintReader) window.PrintReader.postMessage('prev_chapter'); }, 300);
            }
        }
    }
})();