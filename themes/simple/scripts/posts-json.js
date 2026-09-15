// 在 Hexo 构建时注入全文数据到模板上下文
// 使 layout.ejs 可以访问 postsJSON
hexo.extend.helper.register('postsJSON', function() {
  var data = [];
  this.site.posts.each(function(post) {
    // 优先使用显式 excerpt，否则从正文截取
    var excerptText = '';
    if (post.excerpt) {
      excerptText = post.excerpt;
    } else if (post.content) {
      excerptText = this.strip_html(post.content).replace(/\s+/g, ' ').trim().slice(0, 200);
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
