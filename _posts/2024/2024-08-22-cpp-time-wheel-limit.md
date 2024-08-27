---
layout: post
title:  "[C++] 使用时间轮实现对象的操作频率"
categories: c/c++
author: wenfh2020
---

需求：限制用户一段时间内的发包数量。

实现：想了不少方案，最终确认使用时间轮实现。




---

* content
{:toc}

## 1. 时间轮

时钟，大家应该不陌生，12 个刻度，每个大刻度 5 分钟。无论时钟上的针怎么转，都在 12 个刻度范围内，所以这个思路非常适合解决一段时间内的业务逻辑统计。

1. 通过数组实现时间轮。
2. 数组每个下标表示一个刻度值。
3. 数组大小表示刻度个数。
4. 时间轮顺时针转动，当下标轮询到数组的结尾，重新指向数组开始位置，从而形成一个时间环。
5. 时间轮转动过程中，向前转动，会覆盖以前的旧数据。

> 下图是时间轮转一个刻度的图示。

<div align=center><img src="/images/2024/2024-08-27-16-05-10.png" width="85%" data-action="zoom"></div>

---

## 2. 实现

核心算法：根据时间转动的轮子： `CRateLimitMgr::RotateWheel`。

1. nSlots：槽个数，表示刻度个数。
2. nSlotDuration：每个槽代表的时间段（单位：秒）
3. nMsgLimitCnt： 整个时间段内，限制的操作数量。

* 源码。

```cpp
// 管理对象一个时间段内的操作数量
class CRateLimitMgr {
public:
    CRateLimitMgr();
    virtual ~CRateLimitMgr();

    // nSlots: 槽个数
    // nSlotDuration: 每个槽的时间段（单位：秒）
    // nMsgLimitCnt: （nSlots * nSlotDuration）时间段内允许操作消息的条数
    bool Init(int nSlots, int nSlotDuration, int nMsgLimitCnt) {
        std::lock_guard<std::mutex> lock(m_mtx);
        m_nSlots = nSlots;
        m_nMsgLimitCnt = nMsgLimitCnt;
        m_nSlotDuration = nSlotDuration;
    }

    // 增加数量
    bool IncrCnt(const std::string& strObjId) {
        if (nSlots <= 0 || nSlotDuration <= 0 || nMsgLimitCnt <=0) {
            return false;
        }
        std::lock_guard<std::mutex> lock(m_mtx);

        auto it = m_umapObj.find(strObjId);
        if (it == m_umapObj.end()) {
            auto obj = std::make_shared<SLimitObject>(strObjId, m_nSlots,
                std::chrono::steady_clock::now());
            m_mapObj[strObjId] = obj;
            it = m_umapObj.insert(std::make_pair(strObjId, obj)).first;
        }

        auto& obj = it->second;
        RotateWheel(obj);

        if (obj->m_nMsgTotalCnt >= m_nMsgLimitCnt) {
            return false;
        }

        obj->m_vecWheel[obj->m_nCurSlot]++;
        obj->m_nMsgTotalCnt++;
        return true;
    }
    
    // 是否已被限制
    bool IsLimited(const std::string& strObjId) {
        std::lock_guard<std::mutex> lock(m_mtx);
        auto it = m_umapObj.find(strObjId);
        if (it == m_umapObj.end()) {
            return false;
        }
        auto& obj = it->second;
        RotateWheel(obj);
        return obj->m_nMsgTotalCnt >= m_nMsgLimitCnt;
    }

private:
    struct SLimitObject {
        explicit SLimitObject(const std::string& strId, int nSlots, 
            const std::chrono::steady_clock::time_point& tp) 
            : m_strId(strId), m_vecWheel(nSlots, 0), m_tpLastRotation(tp) {}

        std::string m_strId;          // 对象 ID
        int m_nCurSlot = 0;           // 时间轮，当前指向槽位置
        int m_nMsgTotalCnt = 0;       // 消息总数
        std::vector<int> m_vecWheel;  // 记录时间轮每个槽上的操作数量
        // 记录最近一次执行轮换操作的时间点
        std::chrono::steady_clock::time_point m_tpLastRotation;
    };

    // 转动时间轮，重算对象统计的数据
    void RotateWheel(std::shared_ptr<SLimitObject>& userWheel) {
        // 获取当前时间点
        auto tpNow = std::chrono::steady_clock::now();
        // 计算自上次轮换以来经过的秒数
        auto nElapsed = std::chrono::duration_cast<std::chrono::seconds>(
            tpNow - obj->m_tpLastRotation).count();
        // 计算经过的完整轮盘槽数
        int nElapsedSlots = nElapsed / m_nSlotDuration;

        // 如果经过的槽数大于 0，则需要更新轮盘（顺时针）
        if (nElapsedSlots > 0) {
            // 计算实际需要更新的槽数，不能超过总槽数
            int nSlotsToUpdate = std::min(nElapsedSlots, m_nSlots);
            // 遍历需要更新的槽数
            for (int i = 1; i <= nSlotsToUpdate; i++) {
                // 计算当前槽的索引
                int nSlotIndex = (obj->m_nCurSlot + i) % m_nSlots;
                // 从总消息计数中减去当前槽的消息数
                obj->m_nMsgTotalCnt -= obj->m_vecWheel[nSlotIndex];
                // 将当前槽的消息数重置为 0
                obj->m_vecWheel[nSlotIndex] = 0;
            }
            // 更新当前槽的索引
            obj->m_nCurSlot = (obj->m_nCurSlot + nSlotsToUpdate) % m_nSlots;
            // 更新上次轮换时间点，设置为当前槽的开始时间
            obj->m_tpLastRotation = tpNow - std::chrono::seconds(nElapsed % m_nSlotDuration);
        }
    }

private:
    std::mutex m_mtx;
    int m_nSlots = 0;        // 时间轮：槽个数
    int m_nSlotDuration = 0; // 时间轮：每个槽的时间段（精度：秒）
    int m_nMsgLimitCnt = 0;  //（nSlots * nSlotDuration）时间段内允许操作消息的条数
    // 哈希结构记录限制对象，查询效率高
    std::unordered_map<std::string, std::shared_ptr<SLimitObject>> m_umapObj;
};
```

* 测试源码。

```cpp
void testNormal() {
    int nUserId = 1;
    CRateLimitMgr limit;
    if (limit.Init(4, 10, 20, 100)) {
        const int nTotal = 50;
        for (int i = 1; i <= nTotal; i++) {
            if (limit.IncrCnt(nUserId)) {
                printf("msg ok: %d\n", i);
            } else {
                printf("msg xx: %d\n", i);
            }
        }
    }
}

int main() {
    testNormal();
    return 0;
}
```
