# P1-01 运行时锁定

**Files:**

- Create: `test/p1/runtime_manifest.schema.json`
- Create: `test/p1/write_runtime_manifest.py`
- Modify: `test/engines/install_engines.sh`（已存在则只补哈希字段）
- Modify: `SimuNow/Backend/src/simunow_worker/__main__.py`
- Test: `SimuNow/Backend` 或 `test/p1` 下对 doctor JSON 的断言脚本
- Evidence: `test/outputs/p1_runtime/runtime_manifest.json`

**Interfaces:**

- Consumes: `SIMUNOW_ENGINES_ROOT`（目录内有 `MANIFEST.json` 与 `EnergyPlus/energyplus`）
- Produces: `runtime_manifest.json`，字段见 P1-01c；doctor stdout JSON 增加 `engines.l1` / `engines.l2` 对象

---

### P1-01a 锁定 OpenFOAM

- [x] 在容器内打印并保存：`WM_PROJECT_VERSION`、`blockMesh`、`buoyantBoussinesqSimpleFoam` 的绝对路径
- [x] 记录 `docker image inspect simunow/openfoam:2512` 的 `Os/Architecture` 必须为 `linux/arm64`
- [x] 明确求解器名：`buoyantBoussinesqSimpleFoam`；禁止混用 Foundation 教程的 `foamRun`

验收命令：

```bash
docker run --rm --platform linux/arm64 simunow/openfoam:2512 \
  bash -lc 'echo WM_PROJECT_VERSION=$WM_PROJECT_VERSION; command -v buoyantBoussinesqSimpleFoam'
```

通过：版本含 `v2512`，求解器路径非空。失败：镜像缺失或变成 amd64 qemu。

### P1-01b 锁定 EnergyPlus 与天气

- [x] `energyplus --version` 输出含 `25.2.0-cf7368216c`
- [x] 对 EPW 做 SHA-256，写入 manifest（文件名可保留 Hong Kong CityUHK）
- [x] 二进制路径来自 `$SIMUNOW_ENGINES_ROOT/EnergyPlus/energyplus`，禁止写死用户名路径

```bash
export SIMUNOW_ENGINES_ROOT="<engines 根目录>"
"$SIMUNOW_ENGINES_ROOT/EnergyPlus/energyplus" --version
shasum -a 256 "$SIMUNOW_ENGINES_ROOT/weather/"*.epw
```

通过：版本字符串匹配且哈希稳定。失败：quarantine 无法执行、或用了别的 EPW 却不记账。

### P1-01c runtime manifest

- [x] 生成 JSON，至少含：

```json
{
  "host": {"os": "darwin", "machine": "arm64"},
  "openfoam": {
    "image": "opencfd/openfoam-run:2512",
    "local_tag": "simunow/openfoam:2512",
    "platform": "linux/arm64",
    "solver": "buoyantBoussinesqSimpleFoam",
    "project_version": "v2512"
  },
  "energyplus": {
    "version": "25.2.0-cf7368216c",
    "binary": "<relative or env-expanded>",
    "epw_sha256": "<64 hex>"
  },
  "probe": {"rss_peak_mb": 0, "notes": []}
}
```

通过：文件存在且通过 schema 校验。失败：缺字段或绝对 Desktop 路径进了仓库。

### P1-01d doctor

- [x] `PYTHONPATH=Backend/src python3 -m simunow_worker doctor` 在引擎可用时，`engines.l1.status` 为 `configured`，`engines.l2.status` 为 `configured`
- [x] 引擎缺失时保持明确未配置，并给出「运行 `test/engines/install_engines.sh`」类修复路径，**不下载**
- [x] 不在 doctor 里执行求解

通过：两次调用（有/无 `SIMUNOW_ENGINES_ROOT`）JSON 可区分。失败：启动时联网安装，或有引擎仍写死 `not_configured`。

### P1-01e 资源记账

- [x] 对本机 `uname -m`、Docker 内存上限、一次 `blockMesh` 的 max RSS 写入 `probe`
- [x] 单位 MB，注明 macOS `ru_maxrss` 是字节

通过：manifest 里有数字且来源注释在旁边。失败：编造内存或抄别人机器的数。
