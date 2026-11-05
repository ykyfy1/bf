#!/bin/bash
# ====================== HB合并仓库脚本【和扫描仓库保持一致访问方式】 ======================
# Secrets：M3U_URL1 M3U_URL2，直接填入完整 https://user:pass@xxx.pages.dev/zubo.m3u

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

# 合并两个m3u，只保留1个#EXTM3U表头
> zubo.txt
# 写入表头
echo "#EXTM3U" > zubo.txt
# 跳过repo1的#EXTM3U，追加频道内容
grep -v "^#EXTM3U" repo1.m3u >> zubo.txt
# 跳过repo2的#EXTM3U，追加频道内容
grep -v "^#EXTM3U" repo2.m3u >> zubo.txt

# 去重，保留顺序
awk '!seen[$0]++' zubo.txt > zubo_tmp.txt
mv zubo_tmp.txt zubo.txt

# 生成最终播放用m3u
cp zubo.txt zubo.m3u

# 生成index.html兜底页面
echo "<pre>IPTV源：<a href='./zubo.m3u'>zubo.m3u</a></pre>" > index.html

# =========【完全照搬扫描仓库的鉴权中间件，一字不变】=========
# CF Pages Function放在根目录functions
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
      headers: { "WWW-Authenticate": 'Basic realm="IPTV"' },
    });
  }

  const [, base64] = authHeader.split(" ");
  const [user, pass] = atob(base64).split(":");
  if (user !== username || pass !== password) {
    return new Response("账号密码错误", { status: 401 });
  }
  return next();
}
EOF

# 打包静态文件到dist（wrangler部署dist目录，和采集仓库逻辑对齐）
mkdir -p dist
cp zubo.m3u index.html dist/
cp -r functions dist/

echo "✅ 合并完成！输出dist/zubo.m3u，鉴权中间件和扫描仓库完全一致"
echo "==== 合并后总行数：$(wc -l zubo.txt)"
