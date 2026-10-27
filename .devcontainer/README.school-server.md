在 school_server 上进入开发容器：

```sh
docker exec -it -w /workspaces/OS-Course-Lab os-course-lab-dev bash
make
make qemu
```

QEMU 退出操作：先按 Ctrl-a，再按 x。

VS Code：通过 Remote SSH 连接 school_server，执行 Dev Containers: Attach to Running Container，选择 os-course-lab-dev，打开 /workspaces/OS-Course-Lab。也可以在服务器打开仓库，执行 Dev Containers: Reopen in Container。

容器镜像构建：

```sh
cd ~/workspace/kernel/OS-Course-Lab
docker build -t chcore-school-server:local -f .devcontainer/Dockerfile.school-server .devcontainer
```

镜像依赖服务器已有的 oscourselab-devcontainer:latest，包含 AArch64 交叉编译器、QEMU、clangd-16、gdb-multiarch。开发用户 stu 的 UID/GID 为 1012，与服务器账号一致。项目通过目录挂载保存。

调试命令：make qemu-gdb；结束调试：make qemu-gdb-stop。VS Code 使用仓库已有的 QEMU (cppdbg) 调试配置。
