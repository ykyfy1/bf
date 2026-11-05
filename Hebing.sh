#!/bin/bash
# ====================== 合并远端2个zubo.m3u，合并后同时输出 zubo.m3u 和加密 zubo.enc ======================
# Secrets：ENC_URL1 ENC_URL2 填入远端两个CF pages的zubo.m3u链接
# ENCRYPT_PASS：openssl加密密码，用于生成zubo.enc

# 配置参数
CITY_TOP_COUNT=30
MERGE_TOP_COUNT=100
MIN_SPEED_KB=30

# 清理旧文件
rm -rf txt repo1.m3u repo2.m3u raw_merge.txt zubo.txt zubo.enc zubo.m3u functions
mkdir -p txt

# ========== 自动生成鉴权middleware（网页访问密码，和扫描仓库原版一致） ==========
mkdir -p functions
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, env }) {
  const user = env.BASIC_AUTH_USERNAME;
  const pass = env.BASIC_AUTH_PASSWORD;

  const authHeader = request.headers.get('authorization') || '';
  const base64Str = btoa(`${user}:${pass}`);
  if (authHeader !== `Basic ${base64Str}`) {
    return new Response('需要密码', {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="Login"',
        'Cache-Control': 'no-cache, no-store'
      }
    })
  }
  return await env.next.call(request);
}
EOF
# ============================================================================

echo "===== 下载远端两个 zubo.m3u ====="
curl -sL "${ENC_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${ENC_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 1; }

echo "===== 提取播放链接，去掉#EXTM3U等头部标记，合并去重 ====="
# 提取所有非注释行（保留地址行），合并去重
grep -v '^#' repo1.m3u > raw_merge.txt
grep -v '^#' repo2.m3u >> raw_merge.txt
sort -u raw_merge.txt > zubo.txt

# ========= 这里可以恢复你的速度/城市筛选逻辑 =========
# awk -F',' '$NF >= '"${MIN_SPEED_KB}"'' zubo.txt > tmp.txt && mv tmp.txt zubo.txt
# ======================================================

echo "===== 生成合并后的播放列表 zubo.m3u ====="
echo "#EXTM3U" > zubo.m3u
while IFS= read -r line;do
  if [ -n "$line" ];then
    echo "#EXTINF:-1,IPTV" >> zubo.m3u
    echo "${line}" >> zubo.m3u
  fi
done < zubo.txt

echo "===== 将合并后的内容加密输出 zubo.enc（AES-256-CBC -md md5） ====="
openssl enc -aes-256-cbc -md md5 -k "${ENCRYPT_PASS}" -in zubo.txt -out zubo.enc

echo "✅处理完成！输出文件：zubo.m3u  zubo.enc"
ls -la
