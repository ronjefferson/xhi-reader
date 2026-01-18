console.log("Reader JS");

function scrollPage(x) { window.scrollBy({left: x, behavior: 'smooth'}); }

window.nextPage = function() {
    if (window.scrollX + window.innerWidth < document.body.scrollWidth - 10) {
        scrollPage(window.innerWidth);
    } else {
        if(window.FlutterChannel) window.FlutterChannel.postMessage("next");
    }
};

window.prevPage = function() {
    if (window.scrollX > 10) {
        scrollPage(-window.innerWidth);
    } else {
        if(window.FlutterChannel) window.FlutterChannel.postMessage("prev");
    }
};

document.addEventListener("click", function(e) {
    if (e.clientX > window.innerWidth * 0.7) window.nextPage();
    else if (e.clientX < window.innerWidth * 0.3) window.prevPage();
});