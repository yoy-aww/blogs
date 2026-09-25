// 在 Hexo 构建时注入全文数据到模板上下文
// 使用 hexo.model.post 获取完整文章内容（含正文）
hexo.extend.helper.register('postsJSON', function() {
  var data = [];
  var self = this;
  self.site.posts.each(function(post) {
    var rawContent = post.content || '';
    var excerptText = '';
    if (post.excerpt) {
      excerptText = post.excerpt;
    } else if (rawContent) {
      // 去除 markdown/HTML 标签，取前 200 字符
      var plain = rawContent
        .replace(/```[\s\S]*?```/g, ' ')
        .replace(/`[^`]+`/g, ' ')
        .replace(/!\[.*?\]\(.*?\)/g, ' ')
        .replace(/\[.*?\]\(.*?\)/g, ' ')
        .replace(/<[^>]+>/g, ' ')
        .replace(/[#*_~`>|]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
      excerptText = plain.slice(0, 200);
    }
    data.push({
      title: post.title,
      path: post.path,
      type: post.type || 'thought',
      date: post.date.toISOString().slice(0, 10),
      dateLabel: post.date.format('YYYY-MM-DD HH:MM'),
      tags: (post.tags || []).map(function(t) { return t.name; }),
      excerpt: excerptText
    });
  });
  return JSON.stringify(data);
});
