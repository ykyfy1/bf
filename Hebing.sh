#!/bin/bash
# ====================== 从M3U_URL_LIST读取多个远端m3u，严格按demo.txt顺序，同频道全部链接放一起 ======================
# Secrets：M3U_URL_LIST，多行，一行一个m3u链接

# 清理旧文件
rm -rf txt repo_*.m3u tmp_all.txt tmp_extinfo.txt ch_data.txt zubo.m3u
mkdir -p txt

echo "===== 读取M3U_URL_LIST，批量下载所有远端m3u ====="
# 循环读取每一行链接
count=1
while IFS= read -r url; do
  # 跳过空行
  [[ -z "$url" ]] && continue
  echo "下载源${count}: $url"
  curl -sL "${url}" -o "repo_${count}.m3u" || { echo "❌源${count}下载失败"; exit 1; }
  count=$((count+1))
done <<< "${M3U_URL_LIST}"

# 合并全部下载好的m3u文件到tmp_all.txt
cat repo_*.m3u > tmp_all.txt

# 构建【频道名 -> 所有#EXTINF行+url行】的映射
declare -A ch_data
current_ext=""

# 遍历m3u，读取EXTINF和对应播放链接
while IFS= read -r line; do
    if [[ "$line" == "#EXTINF:"* ]]; then
        current_ext="$line"
        # 提取逗号后面的频道名称
        chname=$(echo "$current_ext" | sed -E 's/.*,(.+)$/\1/')
        continue
    fi
    # 是播放链接，并且前面存在EXTINF
    if [[ -n "$current_ext" && "$line" != "#"* && -n "$line" ]]; then
        ch_data["$chname"]+="$current_ext"$'\n'"$line"$'\n'
        current_ext=""
    fi
done < tmp_all.txt

# 按demo.txt顺序生成最终m3u
echo "#EXTM3U" > zubo.m3u

while IFS= read -r line; do
    raw_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [[ -z "$raw_line" ]] && continue

    # 处理分组行 例如：上海电信,#genre#
    if [[ "$raw_line" == *,#genre# ]]; then
        group_name="${raw_line%,#genre#}"
        echo "#EXTINF:-1 tvg-logo=\"\" group-title=\"${group_name}\",${group_name}" >> zubo.m3u
        continue
    fi

    # 普通频道，输出该频道收集的全部EXTINF+链接
    ch_name="$raw_line"
    if [[ -n "${ch_data[$ch_name]}" ]]; then
        echo -n "${ch_data[$ch_name]}" >> zubo.m3u
    fi
done < demo.txt

echo "✅ 合并完成，输出 zubo.m3u"
echo "📄 源数量: $((count-1)) | 严格跟随demo.txt频道顺序，同频道所有IP连续排列"
ls -lh zubo.m3u
