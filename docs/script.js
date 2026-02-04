/**
 * SlothyTerminal Landing Page Scripts
 * "Take it slow, ship it fast."
 */

(function() {
  'use strict';

  // ============================================
  // Theme Toggle
  // ============================================
  const themeToggle = document.getElementById('themeToggle');
  const prefersDark = window.matchMedia('(prefers-color-scheme: dark)');

  function getStoredTheme() {
    return localStorage.getItem('theme');
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
  }

  function initTheme() {
    const stored = getStoredTheme();
    if (stored) {
      setTheme(stored);
    } else {
      // Default to dark mode as per guidelines
      setTheme('dark');
    }
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute('data-theme');
    const next = current === 'dark' ? 'light' : 'dark';
    setTheme(next);
  }

  themeToggle.addEventListener('click', toggleTheme);

  // Listen for system preference changes
  prefersDark.addEventListener('change', (e) => {
    if (!getStoredTheme()) {
      setTheme(e.matches ? 'dark' : 'light');
    }
  });

  initTheme();

  // ============================================
  // Smooth Scroll for Navigation
  // ============================================
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      if (href === '#') return;

      e.preventDefault();
      const target = document.querySelector(href);
      if (target) {
        const navHeight = document.querySelector('.nav').offsetHeight;
        const targetPosition = target.getBoundingClientRect().top + window.pageYOffset - navHeight - 20;

        window.scrollTo({
          top: targetPosition,
          behavior: 'smooth'
        });
      }
    });
  });


  // ============================================
  // Navigation Background on Scroll
  // ============================================
  const nav = document.querySelector('.nav');
  let lastScroll = 0;

  window.addEventListener('scroll', () => {
    const currentScroll = window.pageYOffset;

    if (currentScroll > 100) {
      nav.style.boxShadow = '0 4px 20px rgba(0, 0, 0, 0.15)';
    } else {
      nav.style.boxShadow = 'none';
    }

    lastScroll = currentScroll;
  }, { passive: true });

  // ============================================
  // Copy Code Block (optional enhancement)
  // ============================================
  document.querySelectorAll('.code-block').forEach(block => {
    block.style.cursor = 'pointer';
    block.title = 'Click to copy';

    block.addEventListener('click', async () => {
      const code = block.querySelector('code');
      const text = code.innerText
        .split('\n')
        .map(line => line.replace(/^❯\s*/, ''))
        .join('\n')
        .trim();

      try {
        await navigator.clipboard.writeText(text);

        // Visual feedback
        const originalBg = block.style.background;
        block.style.background = 'var(--accent-glow)';
        setTimeout(() => {
          block.style.background = originalBg;
        }, 200);
      } catch (err) {
        console.error('Failed to copy:', err);
      }
    });
  });

  // ============================================
  // Keyboard Navigation Enhancement
  // ============================================
  document.addEventListener('keydown', (e) => {
    // Toggle theme with 't' key (when not in input)
    if (e.key === 't' && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
      toggleTheme();
    }
  });

  // ============================================
  // Preload hero image for smoother experience
  // ============================================
  const heroIcon = document.querySelector('.hero-icon');
  if (heroIcon) {
    const img = new Image();
    img.src = heroIcon.src;
  }

  // ============================================
  // Screenshot Carousel
  // ============================================
  const carousel = document.getElementById('screenshotCarousel');
  if (carousel) {
    const slides = carousel.querySelectorAll('.carousel-slide');
    const dots = carousel.querySelectorAll('.carousel-dot');
    const prevBtn = carousel.querySelector('.carousel-btn-prev');
    const nextBtn = carousel.querySelector('.carousel-btn-next');

    let currentIndex = 0;
    let autoplayInterval = null;
    const autoplayDelay = 5000;

    function goToSlide(index) {
      // Handle wraparound
      if (index < 0) {
        index = slides.length - 1;
      } else if (index >= slides.length) {
        index = 0;
      }

      currentIndex = index;

      // Update slides - show only active
      slides.forEach((slide, i) => {
        slide.classList.toggle('active', i === currentIndex);
      });

      // Update dots
      dots.forEach((dot, i) => {
        dot.classList.toggle('active', i === currentIndex);
      });
    }

    function nextSlide() {
      goToSlide(currentIndex + 1);
    }

    function prevSlide() {
      goToSlide(currentIndex - 1);
    }

    function startAutoplay() {
      stopAutoplay();
      autoplayInterval = setInterval(nextSlide, autoplayDelay);
    }

    function stopAutoplay() {
      if (autoplayInterval) {
        clearInterval(autoplayInterval);
        autoplayInterval = null;
      }
    }

    // Event listeners
    prevBtn.addEventListener('click', () => {
      prevSlide();
      startAutoplay();
    });

    nextBtn.addEventListener('click', () => {
      nextSlide();
      startAutoplay();
    });

    dots.forEach((dot, index) => {
      dot.addEventListener('click', () => {
        goToSlide(index);
        startAutoplay();
      });
    });

    // Pause autoplay on hover
    carousel.addEventListener('mouseenter', stopAutoplay);
    carousel.addEventListener('mouseleave', startAutoplay);

    // Touch/swipe support
    let touchStartX = 0;

    carousel.addEventListener('touchstart', (e) => {
      touchStartX = e.changedTouches[0].screenX;
      stopAutoplay();
    }, { passive: true });

    carousel.addEventListener('touchend', (e) => {
      const touchEndX = e.changedTouches[0].screenX;
      const diff = touchStartX - touchEndX;

      if (Math.abs(diff) > 50) {
        if (diff > 0) {
          nextSlide();
        } else {
          prevSlide();
        }
      }
      startAutoplay();
    }, { passive: true });

    // Start autoplay
    startAutoplay();

    // Pause when tab is not visible
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        stopAutoplay();
      } else {
        startAutoplay();
      }
    });
  }

  // ============================================
  // Image Lightbox
  // ============================================
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = document.getElementById('lightboxImg');
  const lightboxClose = lightbox?.querySelector('.lightbox-close');
  const lightboxPrev = lightbox?.querySelector('.lightbox-btn-prev');
  const lightboxNext = lightbox?.querySelector('.lightbox-btn-next');

  const carouselImages = Array.from(document.querySelectorAll('.carousel-img'));
  let currentLightboxIndex = 0;

  function showLightboxImage(index) {
    if (!lightboxImg || carouselImages.length === 0) {
      return;
    }

    // Wrap around
    if (index < 0) {
      index = carouselImages.length - 1;
    } else if (index >= carouselImages.length) {
      index = 0;
    }

    currentLightboxIndex = index;
    const img = carouselImages[index];
    lightboxImg.src = img.src;
    lightboxImg.alt = img.alt || '';
  }

  function openLightbox(index) {
    if (!lightbox || !lightboxImg) {
      return;
    }

    showLightboxImage(index);
    lightbox.classList.add('active');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    if (!lightbox) {
      return;
    }

    lightbox.classList.remove('active');
    document.body.style.overflow = '';
  }

  function lightboxPrevImage() {
    showLightboxImage(currentLightboxIndex - 1);
  }

  function lightboxNextImage() {
    showLightboxImage(currentLightboxIndex + 1);
  }

  // Click on carousel images to open lightbox
  carouselImages.forEach((img, index) => {
    img.addEventListener('click', (e) => {
      e.stopPropagation();
      openLightbox(index);
    });
  });

  // Navigation buttons
  if (lightboxPrev) {
    lightboxPrev.addEventListener('click', (e) => {
      e.stopPropagation();
      lightboxPrevImage();
    });
  }

  if (lightboxNext) {
    lightboxNext.addEventListener('click', (e) => {
      e.stopPropagation();
      lightboxNextImage();
    });
  }

  // Close lightbox on backdrop click
  if (lightbox) {
    lightbox.addEventListener('click', (e) => {
      if (e.target === lightbox) {
        closeLightbox();
      }
    });
  }

  // Close button
  if (lightboxClose) {
    lightboxClose.addEventListener('click', closeLightbox);
  }

  // Keyboard navigation
  document.addEventListener('keydown', (e) => {
    if (!lightbox?.classList.contains('active')) {
      return;
    }

    if (e.key === 'Escape') {
      closeLightbox();
    } else if (e.key === 'ArrowLeft') {
      lightboxPrevImage();
    } else if (e.key === 'ArrowRight') {
      lightboxNextImage();
    }
  });

})();
