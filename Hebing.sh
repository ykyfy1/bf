#!/bin/bash
# 合并远端2个m3u，生成明文zubo.m3u(CF BASIC鉴权) + 加密包zubo.enc
# 环境变量：M3U_URL1 M3U_URL2 ENCRYPT_PASS

# 清理旧文件
rm -rf repo1.m3u repo2.m3u zubo.m3u zubo.enc _middleware.js
mkdir -p tmp

echo "===== 下载远端两个 m3u ====="
curl -sL "${M3U_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${M3U_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 1; }

echo "文件1大小: $(du -h repo1.m3u)"
echo "文件2大小: $(du -h repo2.m3u)"

# 合并 + 去重，只保留一次#EXTM3U
{
  echo "#EXTM3U"
  grep -v "#EXTM3U" repo1.m3u
  grep -v "#EXTM3U" repo2.m3u
} | awk '!seen[$0]++' > zubo.m3u

echo "✅m3u合并完成，输出 zubo.m3u"
echo "m3u最终行数：$(wc -l zubo.m3u)"

# AES-256-CBC 文件加密，生成zubo.enc（供其他仓库拉取解密合并）
echo "开始加密..."
openssl enc -aes-256-cbc -md md5 -in zubo.m3u -out zubo.enc -k "${ENCRYPT_PASS}"
if [ $? -ne 0 ];then
  echo "❌openssl加密失败！"
  exit 1
fi
echo "✅加密完成，生成 zubo.enc"

# 生成中间件，读取CF项目内 BASIC_AUTH_USERNAM / BASIC_AUTH_PASSWOR
cat > _middleware.js <<'EOF'
export async function onRequest({ request, next, env }) {
  const USER = env.BASIC_AUTH_USERNAM;
  const PASS = env.BASIC_AUTH_PASSWOR;

  const authHeader = request.headers.get("authorization");
  const noCacheHeaders = {
    "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
    "Pragma": "no-cache",
    "Expires": "0"
  };

  if (!authHeader) {
    return new Response("需要登录", {
      status: 401,
      headers: {
        "WWW-Authenticate": 'Basic realm="需要密码访问"',
        ...noCacheHeaders
      }
    })
  }
  const [, base64] = authHeader.split(" ")
  const decoded = atob(base64).split(":")
  const user = decoded[0]
  const pass = decoded[1]
  if (user === USER && pass === PASS) {
    const response = await next();
    Object.entries(noCacheHeaders).forEach(([k,v])=>response.headers.set(k,v))
    return response;
  }
  return new Response("账号密码错误", {
    status: 401,
    headers: noCacheHeaders
  })
}
EOF
echo "✅生成 _middleware.js，读取CF项目内置密钥"

ls -lh zubo.m3u zubo.enc _middleware.js
