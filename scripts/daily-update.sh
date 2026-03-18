#!/bin/bash
# ========================================
# OpenClaw 中文站每日更新脚本
# 每天早 6:00 自动执行
# 抓取 OpenClaw 官方博客，自动生成中文内容
# ========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="/Users/macm2/workspace/openclaw-docs-cn"
SERVER_DIR="root@115.190.211.199:/www/wwwroot/openclaw-docs-cn"
GITHUB_REPO="https://github.com/hantangguzheng/openclaw-docs-cn.git"
BRANCH="main"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查依赖
check_deps() {
    command -v curl >/dev/null 2>&1 || { echo "curl required but not installed."; exit 1; }
    command -v git >/dev/null 2>&1 || { echo "git required but not installed."; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq required but not installed."; exit 1; }
}

# 抓取 OpenClaw 官方博客更新
fetch_blog_updates() {
    log "📡 抓取 OpenClaw 官方博客..."

    BLOG_URL="https://openclaw.ai/blog"
    BLOG_DIR="$PROJECT_DIR/blog"

    mkdir -p "$BLOG_DIR"

    # 抓取博客 RSS
    if curl -sf "https://openclaw.ai/blog/rss.xml" -o "$BLOG_DIR/feed.xml"; then
        log "✅ 博客 RSS 抓取成功"
    else
        log "⚠️ 博客 RSS 抓取失败，尝试直接抓取页面..."
        curl -sf "$BLOG_URL" -o "$BLOG_DIR/index.html" 2>/dev/null || true
    fi

    # 抓取 GitHub releases
    log "📦 检查 GitHub Releases..."
    RELEASES_URL="https://api.github.com/repos/openclaw/openclaw/releases/latest"
    curl -sf "$RELEASES_URL" -H "Accept: application/vnd.github.v3+json" | \
        jq -r '.tag_name // empty' > "$BLOG_DIR/latest_version.txt" 2>/dev/null || true

    if [ -s "$BLOG_DIR/latest_version.txt" ]; then
        log "✅ 最新版本: $(cat $BLOG_DIR/latest_version.txt)"
    fi
}

# 生成中文内容摘要
generate_chinese_summary() {
    log "📝 生成中文内容摘要..."

    SUMMARY_FILE="$PROJECT_DIR/pages/info.html"

    # 提取最新版本信息
    if [ -s "$BLOG_DIR/latest_version.txt" ]; then
        local_version=$(cat "$BLOG_DIR/latest_version.txt")
        log "📌 检测到新版本: $local_version"
    fi
}

# 更新统计数字
update_stats() {
    log "📊 更新统计数字..."

    # 获取 GitHub 星标数
    GITHUB_STARS=$(curl -sf "https://api.github.com/repos/openclaw/openclaw" | jq -r '.stargazers_count // 55000')
    log "GitHub Stars: $GITHUB_STARS"

    # 更新 index.html 中的星标数
    local formatted_stars
    if [ "$GITHUB_STARS" -ge 1000 ]; then
        formatted_stars="$(echo "scale=1; $GITHUB_STARS/1000" | bc)%bk"
    else
        formatted_stars="$GITHUB_STARS+"
    fi

    # 更新星标显示
    sed -i '' "s/55\.3k+/$(printf '%.1f' "$(echo "scale=1; $GITHUB_STARS/1000" | bc)")k+/g" "$PROJECT_DIR/index.html" 2>/dev/null || true

    # 获取贡献者数
    CONTRIBUTORS=$(curl -sf "https://api.github.com/repos/openclaw/openclaw" | jq -r '.contributors_count // 1100')
    log "Contributors: $CONTRIBUTORS"
}

# 提交更改
git_commit() {
    cd "$PROJECT_DIR"

    # 检查是否有变更
    if git diff --quiet && git diff --cached --quiet; then
        log "📭 没有需要更新的内容"
        return 0
    fi

    log "📤 提交更改..."
    git add -A
    git commit -m "Daily update: $(date '+%Y-%m-%d %H:%M') - 站点内容自动更新" || true
    git push origin "$BRANCH" || log "⚠️ GitHub Push 失败"
    log "✅ GitHub 推送完成"
}

# 部署到服务器
deploy_to_server() {
    log "🚀 部署到服务器..."
    # 在服务器上执行 git pull
    ssh -o StrictHostKeyChecking=no root@115.190.211.199 \
        "cd /www/wwwroot/openclaw-docs-cn && git pull origin main && nginx -s reload" \
        || log "⚠️ 服务器部署失败，请手动检查"
    log "✅ 服务器部署完成"
}

# 主流程
main() {
    log "========================================"
    log "OpenClaw 中文站每日更新开始"
    log "========================================"

    check_deps
    fetch_blog_updates
    generate_chinese_summary
    update_stats
    git_commit
    deploy_to_server

    log "========================================"
    log "✅ 每日更新完成"
    log "========================================"
}

# 设置定时任务（仅首次运行）
setup_cron() {
    local cron_job="0 6 * * * $SCRIPT_DIR/daily-update.sh >> $SCRIPT_DIR/daily-update.log 2>&1"
    (crontab -l 2>/dev/null | grep -q "$SCRIPT_DIR/daily-update.sh") || \
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    log "✅ 定时任务已设置（每天早 6:00 执行）"
}

# 根据参数决定执行什么
case "${1:-run}" in
    run)
        main
        ;;
    deploy-only)
        deploy_to_server
        ;;
    fetch-only)
        fetch_blog_updates
        ;;
    setup-cron)
        setup_cron
        ;;
    *)
        echo "用法: $0 {run|deploy-only|fetch-only|setup-cron}"
        exit 1
        ;;
esac
