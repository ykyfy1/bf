#!/bin/bash
# 合并远端2个m3u，输出zubo.m3u + zubo.enc
# Github Secrets: ENC_URL1 ENC_URL2 ENCRYPT_PASS

# 清理旧文件
rm -rf repo1.m3u repo2.m3u zubo.m3u zubo.enc functions
mkdir -p tmp
mkdir -p functions

echo "===== 下载远端两个m3u ====="
curl -sL "${ENC_URL1}" -o repo1.m3u || { echo "❌仓库1 m3u下载失败"; exit 1; }
curl -sL "${ENC_URL2}" -o repo2.m3u || { echo "❌仓库2 m3u下载失败"; exit 1; }

echo "文件1大小: $(du -h repo1.m3u)"
echo "文件2大小: $(du -h repo2.m3u)"

# 合并去重m3u，只保留一次#EXTM3U
{
  echo "#EXTM3U"
  grep -v "#EXTM3U" repo1.m3u
  grep -v "#EXTM3U" repo2.m3u
} | awk '!seen[$0]++' > zubo.m3u

echo "✅合并完成，zubo.m3u行数：$(wc -l zubo.m3u)"

# AES加密生成zubo.enc
echo "===== 加密生成zubo.enc ====="
openssl enc -aes-256-cbc -md md5 -in zubo.m3u -out zubo.enc -k "${ENCRYPT_PASS}"
if [ $? -ne 0 ];then
  echo "❌openssl加密失败！"
  exit 1;
fi
echo "✅加密完成"

# 生成【扫描仓库同款Basic鉴权】中间件，读取CF环境变量
cat > functions/_middleware.js <<'EOF'
export async function onRequest({ request, next, env }) {
  const USER = env.BASIC_AUTH_USERNAME;
  const PASS = env.BASIC_AUTH_PASSWORD;

  if (!USER || !PASS) {
    return new Response("配置缺失", { status: 500 });
  }

  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Basic ")) {
    return new Response("需要密码", {
      status: 401,
      headers: {
        "WWW-Authenticate": 'Basic realm="请输入账号密码"',
        "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
        "Pragma": "no-cache",
        "Expires": "0"
      }
    });
  }

  const base64Str = authHeader.split(" ")[1];
  const [username, password] = atob(base64Str).split(":");

  if (username === USER && password === PASS) {
    const resp = await next();
    resp.headers.set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
    return resp;
  }

  return new Response("账号或密码错误", { status: 401 });
}
EOF
echo "✅生成鉴权中间件：functions/_middleware.js"

ls -lh zubo.m3u zubo.enc functions/_middleware.js
