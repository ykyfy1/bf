#!/bin/bash
# ====================== HB合并仓库脚本【完全保留源文件内部顺序，原样拼接，同扫描仓库鉴权+关闭CF缓存】 ======================
# Secrets：M3U_URL1 M3U_URL2，填入完整 https://user:pass@xxx.pages.dev/zubo.m3u

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.m3u repo2.m3u zubo.txt zubo.m3u index.html functions dist
mkdir -p txt

echo "===== 下载远端两个m3u文件 ====="
# 和扫描仓库同源：直接使用完整带BasicAuth的URL
curl -sL "${M3U_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${M3U_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 2; }

echo "repo1.m3u size: $(du -h repo1.m3u)"
echo "repo2.m3u size: $(du -h repo2.m3u)"

# ========== 合并逻辑：保留两个文件各自内部原有顺序，仅剔除多余 #EXTM3U ==========
> zubo.txt
# 写入唯一总表头
echo "#EXTM3U" > zubo.txt

# 把repo1全部内容，去掉#EXTM3U，原样追加（仓库1完整顺序）
sed '/^#EXTM3U/d' repo1.m3u >> zubo.txt
# 把repo2全部内容，去掉#EXTM3U，原样追加在末尾（仓库2完整顺序接在后面）
sed '/^#EXTM3U/d' repo2.m3u >> zubo.txt

# 生成最终播放m3u
cp zubo.txt zubo.m3u

# 生成index.html兜底页面
echo "<pre>IPTV源：<a href='./zubo.m3u'>zubo.m3u</a></pre>" > index.html

# =========【扫描仓库同款鉴权 + 关闭CF缓存，解决密码时有时无】=========
mkdir -p functions
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, env, next }) {
  const username = env.BASIC_AUTH_USERNAME;
  const password = env.BASIC_AUTH_PASSWORD;

  if (!username || !password) return next();

  const authHeader = request.headers.get("authorization");
  if (!authHeader) {
    return new Response("需要输入访问密码", {
      status: 401,
      headers: {
        "WWW-Authenticate": 'Basic realm="IPTV"',
        "Cache-Control": "no-store, no-cache, must-revalidate"
      },
    });
  }

  const [, base64] = authHeader.split(" ");
  const [user, pass] = atob(base64).split(":");
  if (user !== username || pass !== password) {
    return new Response("账号密码错误", {
      status: 401,
      headers: { "Cache-Control": "no-store, no-cache, must-revalidate" }
    });
  }
  const response = await next();
  response.headers.set("Cache-Control", "no-store, no-cache, must-revalidate");
  return response;
}
EOF

# 打包静态文件到dist
mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "✅ 合并完成！完全保留两个m3u各自内部原有顺序，原样追加"
echo "==== 合并后总行数：$(wc -l zubo.txt)"
