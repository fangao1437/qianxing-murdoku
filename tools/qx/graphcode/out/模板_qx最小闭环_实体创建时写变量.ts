// 由 tools/qx/graphcode/emit.mjs 从 behavior-spec 生成（target=gts，主路线 = MIT 的 genshin-ts）
// 落盘路径：本文件 → gsts compile → .gia → gsts inject → .gil
// 本工程**不写** protobuf：写入一律交给 genshin-ts 的 injector。
import { g } from 'genshin-ts/runtime/core'

g.server({
  id: 1073741825,
  name: "模板_qx最小闭环_实体创建时写变量"
})
  .on("whenEntityIsCreated", (evt, f) => {
    const 事件源实体 = evt.eventSourceEntity
    const 事件源GUID = evt.eventSourceGuid
    f.printString('qx-min-loop: entity created')
    f.setCustomVariable(事件源实体, 'qx_min_loop_flag', 1n, true)
  })
