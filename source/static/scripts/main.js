// Open external links in a new window/tab.

(function() {
  try {
    document.addEventListener('DOMContentLoaded', function() {
      document.querySelectorAll('a[href]').forEach(link => {
        if (/^https?:\/\//i.test(link.getAttribute('href'))) {
          console.log(link.href)
          link.target = '_blank';
          link.rel = 'noopener noreferrer';
        }
      });
    });
  } catch (e) {
  }
})();
