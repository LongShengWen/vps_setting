# VPS Setting

## 一键运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LongShengWen/vps_setting/main/bootstrap.sh)
```

## 本地运行

```bash
bash vps_init_suite.sh
```

## 目录结构

- `bootstrap.sh`：远程一键入口
- `vps_init_suite.sh`：本地兼容入口
- `main.sh`：主入口
- `lib/01_core_ui.sh`：基础变量、UI、通用函数
- `lib/13_auto_deploy_entry.sh`：全自动部署主流程入口
- `lib/14_system_base.sh`：系统状态、systemd、包管理、下载、输入工具
- `lib/15_ssh_hardening.sh`：SSH、用户、SELinux、Fail2Ban
- `lib/16_perf_tuning.sh`：TCP/BBR、Swap、性能调优
- `lib/17_firewall_backend.sh`：iptables / nftables / firewalld 后端处理
- `lib/03_network_report.sh`：网络、DNS、IPv6、系统报告
- `lib/04_menus_security.sh`：环境基础、安全加固、性能优化、防火墙子菜单
- `lib/05_firewall_advanced.sh`：防火墙总入口
- `lib/06_lucky_docker_compose.sh`：Lucky、Docker、Compose 仓库部署
- `lib/07_machine_tests.sh`：机器测试入口与脚本调用
- `lib/08_nginx.sh`：Nginx、域名/证书/路径通用处理
- `lib/09_3xui.sh`：3x-ui 安装、预置与反向代理配置
- `lib/10_komari.sh`：Komari 安装与反向代理配置
- `lib/11_service_uninstall.sh`：Docker / 3x-ui / Lucky / 1Panel / Nginx / 哪吒卸载
- `lib/12_ops_menu_dd.sh`：运维工具菜单、DD 系统菜单
