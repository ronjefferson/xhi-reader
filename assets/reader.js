window.addEventListener('DOMContentLoaded', () => {

    let startX = 0;
    let startScrollPos = 0;
    let isAnimating = false;

    document.addEventListener('touchstart', (e) => {
        startX = e.changedTouches[0].screenX;
        startScrollPos = window.scrollX;
    }, { passive: true });

    document.addEventListener('touchend', (e) => {
        if (isAnimating) return;

        const endX = e.changedTouches[0].screenX;
        const diff = startX - endX; // +Val = Swipe Left (Next), -Val = Swipe Right (Prev)
        
        // 1. GET MEASUREMENTS
        // Use scrollWidth. If content fits perfectly, scrollWidth == clientWidth.
        const totalWidth = document.body.scrollWidth; 
        const clientWidth = window.innerWidth;
        const maxScroll = totalWidth - clientWidth;
        
        // 2. CHECK POSITIONS (With 5px Buffer)
        // If maxScroll is 0 (Single page), both Start and End are TRUE.
        const isAtStart = startScrollPos <= 5;
        const isAtEnd = startScrollPos >= (maxScroll - 5);

        // 3. CHAPTER NAVIGATION LOGIC
        
        // NEXT CHAPTER:
        // User swiped Left (>50px) AND we started at the physical end.
        if (diff > 50 && isAtEnd) {
            animateAndExit('next');
        }
        
        // PREV CHAPTER:
        // User swiped Right (<-50px) AND we started at the physical start.
        else if (diff < -50 && isAtStart) {
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
});