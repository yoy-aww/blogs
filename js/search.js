// 客户端搜索与过滤脚本
(function() {
  'use strict';

  // 读取 URL 参数
  function getParam(name) {
    return new URLSearchParams(window.location.search).get(name);
  }

  function init() {
    var input = document.getElementById('search-input');
    var list = document.getElementById('post-list');
    var countEl = document.getElementById('result-count');
    if (!input || !list || !countEl) return;

    var posts = window.posts || [];
    var currentType = getParam('type'); // 初始类型过滤
    var currentQuery = getParam('q') || '';

    // 如果有初始查询，填入搜索框
    if (currentQuery) {
      input.value = currentQuery;
    }

    // 过滤并渲染
    function filterAndRender(query, type) {
      var q = (query || '').trim().toLowerCase();
      var filtered = posts.filter(function(p) {
        // 类型过滤
        if (type && p.type !== type) return false;
        // 关键词过滤：标题、标签、摘要
        if (q) {
          var title = (p.title || '').toLowerCase();
          var tags = (p.tags || []).join(',').toLowerCase();
          var excerpt = (p.excerpt || '').toLowerCase();
          return title.indexOf(q) >= 0 || tags.indexOf(q) >= 0 || excerpt.indexOf(q) >= 0;
        }
        return true;
      });

      // 渲染结果
      list.innerHTML = '';
      if (filtered.length === 0) {
        var noResults = document.createElement('div');
        noResults.className = 'no-results';
        noResults.innerHTML = '<i class="fas fa-search"></i><p>没有找到匹配的文章</p>' +
          '<p class="no-results-hint">试试其他关键词，或清除搜索条件</p>';
        list.appendChild(noResults);
      } else {
        filtered.forEach(function(p) {
          var article = document.createElement('article');
          article.className = 'post-item';
          article.setAttribute('data-type', p.type);

          var typeBadge = p.type === 'tech'
            ? '<span class="type-badge type-badge--tech">技术</span>'
            : '<span class="type-badge type-badge--thought">思想</span>';

          var tagsHtml = '';
          (p.tags || []).forEach(function(tag) {
            tagsHtml += '<a href="/tags/' + encodeURIComponent(tag) + '/" class="post-tag">#' + tag + '</a>';
          });

          article.innerHTML =
            '<div class="post-item-header">' +
              '<h2><a href="' + p.path + '">' + p.title + '</a></h2>' +
              '<time>' + p.dateLabel + '</time>' +
            '</div>' +
            '<div class="post-meta-row">' + typeBadge + tagsHtml + '</div>' +
            (p.excerpt ? '<div class="excerpt">' + p.excerpt + '</div>' : '');
          list.appendChild(article);
        });
      }

      // 更新结果数
      countEl.textContent = '共 ' + filtered.length + ' 篇文章' +
        (type ? '（' + (type === 'tech' ? '技术博客' : '思想博客') + '）' : '');

      // 更新过滤按钮状态
      var btns = document.querySelectorAll('.filter-btn');
      btns.forEach(function(btn) {
        var btnType = btn.getAttribute('data-type') ||
          (btn.className.indexOf('filter-btn--thought') >= 0 ? 'thought' : 'tech');
        if (btnType === type) {
          btn.classList.add('filter-btn--active');
        } else {
          btn.classList.remove('filter-btn--active');
        }
      });

      // 更新首页过滤按钮状态（如果存在）
      var homeBtns = document.querySelectorAll('.filter-btn-home');
      homeBtns.forEach(function(btn) {
        var btnType = btn.getAttribute('data-type') ||
          (btn.className.indexOf('filter-btn--thought') >= 0 ? 'thought' : 'tech');
        if (btnType === type) {
          btn.classList.add('filter-btn--active');
        } else {
          btn.classList.remove('filter-btn--active');
        }
      });
    }

    // 监听输入
    var debounceTimer;
    input.addEventListener('input', function() {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function() {
        filterAndRender(input.value, currentType);
      }, 200);
    });

    // 监听过滤按钮点击
    document.querySelectorAll('.filter-btn, .filter-btn-home').forEach(function(btn) {
      btn.addEventListener('click', function(e) {
        e.preventDefault();
        var type = btn.getAttribute('data-type') ||
          (btn.className.indexOf('filter-btn--thought') >= 0 ? 'thought' : 'tech');
        // 再次点击同一类型 = 取消过滤
        if (currentType === type) {
          currentType = null;
          btn.classList.remove('filter-btn--active');
        } else {
          currentType = type;
        }
        filterAndRender(input.value, currentType);

        // 更新 URL（不刷新页面）
        var params = new URLSearchParams();
        if (input.value.trim()) params.set('q', input.value.trim());
        if (currentType) params.set('type', currentType);
        var newUrl = window.location.pathname + (params.toString() ? '?' + params.toString() : '');
        window.history.replaceState(null, '', newUrl);
      });
    });

    // 初始渲染
    filterAndRender(currentQuery, currentType);
  }

  // DOM 就绪后初始化
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
