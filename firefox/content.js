(function() {
    // Ultra-minimalist performance script
    const apply = () => {
        document.documentElement.style.colorScheme = 'dark';
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', apply);
    } else {
        apply();
    }
})();
