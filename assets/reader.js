// STATE
let currentPage = 0;

// SETUP (Reset on load)
function setup() {
    currentPage = 0;
    updateView();
}
// Run setup when content loads
setup();
setTimeout(setup, 300); // Safety check for images


// --- THE API (Called by Flutter) ---

// Returns: 'success' if moved, 'edge' if at the limit
function tryTurnPage(direction) {
    // 1. Recalculate dimensions (Crucial for accuracy)
    const contentWidth = document.body.scrollWidth;
    const screenWidth = window.innerWidth;
    
    // Use -2px buffer to handle sub-pixel rendering issues
    const totalPages = Math.ceil((contentWidth - 2) / screenWidth);
    
    // Calculate Target
    const nextPage = currentPage + direction;

    // --- BOUNDARY CHECKS ---
    
    // A. PREV Edge (Start of Chapter)
    if (nextPage < 0) {
        // We are at the start, tell Flutter to handle "Previous Chapter"
        return 'edge_prev';
    }
    
    // B. NEXT Edge (End of Chapter)
    if (nextPage >= totalPages) {
        // We are at the end, tell Flutter to handle "Next Chapter"
        return 'edge_next';
    }

    // --- EXECUTE SLIDE ---
    currentPage = nextPage;
    updateView();
    return 'success';
}

function updateView() {
    const translateAmount = -(currentPage * 100);
    document.body.style.transform = `translateX(${translateAmount}vw)`;
}