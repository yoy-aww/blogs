/**
 * Note tag for Hexo
 * 
 * Syntax:
 *   {% note [class] [title] %}
 *   content
 *   {% endnote %}
 * 
 * Examples:
 *   {% note info %}
 *   This is an info note
 *   {% endnote %}
 * 
 *   {% note warning Important %}
 *   This is a warning with title
 *   {% endnote %}
 */

hexo.extend.tag.register('note', function(args, content) {
  const className = args[0] || 'default';
  const title = args.slice(1).join(' ') || '';
  
  const classMap = {
    'default': {
      bg: '#f8f9fa',
      border: '#dee2e6',
      icon: '📝',
      color: '#495057'
    },
    'info': {
      bg: '#d1ecf1',
      border: '#bee5eb',
      icon: '💡',
      color: '#0c5460'
    },
    'success': {
      bg: '#d4edda',
      border: '#c3e6cb',
      icon: '✅',
      color: '#155724'
    },
    'warning': {
      bg: '#fff3cd',
      border: '#ffeaa7',
      icon: '⚠️',
      color: '#856404'
    },
    'danger': {
      bg: '#f8d7da',
      border: '#f5c6cb',
      icon: '🚨',
      color: '#721c24'
    }
  };
  
  const style = classMap[className] || classMap['default'];
  
  // 处理内容，支持Markdown渲染
  let processedContent = content.trim();
  if (processedContent) {
    try {
      processedContent = hexo.render.renderSync({text: processedContent, engine: 'markdown'});
      // 移除外层的p标签，但保留内部的HTML结构
      processedContent = processedContent.replace(/^<p>/, '').replace(/<\/p>$/, '');
    } catch (e) {
      // 如果渲染失败，使用原始内容
      processedContent = content.trim();
    }
  }
  
  // 构建标题部分
  const titleHtml = title ? `<div class="note-title">
    <span class="note-icon">${style.icon}</span><strong>${title}</strong>
  </div>` : '';
  
  const iconHtml = title ? '' : `<span class="note-icon">${style.icon}</span> `;
  
  return `<div class="hexo-note hexo-note-${className}" style="background-color: ${style.bg}; border-color: ${style.border}; color: ${style.color};">
    ${titleHtml}${iconHtml}${processedContent}
  </div>`;
}, {ends: true});