---
layout: post
title:  "[QT] 浅析信号与槽"
categories: c/c++
author: wenfh2020
---

QT 的信号与槽技术，是一种用于对象间通信的机制。它允许一个对象发出一个信号，而其他对象可以通过连接到该信号的槽来接收并处理该信号。

本文将通过调试走读 QT (5.14.2) 信号与槽开源源码，理解它的工作原理。



* content
{:toc}



---

## 1. 概述

* QObject 的 `connect` 函数，将 “发送者/信号/接收者/槽/链接类型” 这几个对象建立联系，并保存于 `QObjectPrivate::Connection` 这个信号槽关系结构中。
* 信号与槽是一种 `观察者` 模式，QObject 为每个信号生成一个索引 `signal_index`，用于标识某个信号所在 `signalVector` 动态数组的位置，receiver 信息被保存于数组下标对应的列表中。
  > sender object -> signalVector[signal_index] -> connectionlist -> connection

<div align=center><img src="/images/2023-07-25-11-13-45.png" data-action="zoom"></div>

---

## 2. 测试用例

这是一个多线程的信号与槽测试用例，本文将会通过该用例，描述信号与槽的工作原理。

> 详细源码请参考 [Github](https://github.com/wenfh2020/my_qt_test/tree/main/TestApp)。

<div align=center><img src="/images/2023-07-27-13-43-53-03.gif" data-action="zoom"></div>

```cpp
// 线程测试用例
class TestThread : public WorkThread {
    Q_OBJECT
    
 public signals:
    void sigThreadNotify(qint64 task, const QString& data);

 private:
    virtual void handleTask(qint64 task) override {
        emit sigThreadNotify(task, "hello world!");
    }
};

// 测试窗口
class TestApp : public QMainWindow {
    Q_OBJECT

 public:
    void init() {
        connect(m_thread, &TestThread::sigThreadNotify, this,
            &TestApp::slotThreadNotify);
        connect(ui.btn_work_thread, &QPushButton::clicked, this, [this]() {
            auto msg = QString("send task to work thread, task: %1").arg(TASK_ID);
            QMessageBox::information(this, "tip", msg, QMessageBox::Yes);
            this->appendThreadTask(TASK_ID);
        });
    }
    
 public slots:
    void slotThreadNotify(qint64 task, const QString& data) {
        auto msg = QString("response from work thread, task: %1, data: %2")
                    .arg(task)
                    .arg(data);
        QMessageBox::information(this, "tip", msg, QMessageBox::Yes);
    }

 private:
    Ui::TestAppClass ui;
    TestThread* m_thread = Q_NULLPTR;
};
```

---

## 3. 信号槽关系结构

* 信号槽链接结构体：`QObjectPrivate::Connection`。

```cpp
/*C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject_p.h*/
class Q_CORE_EXPORT QObjectPrivate : public QObjectData {
    ...
    struct Connection : public ConnectionOrSignalVector {
        ...
         /*发送者*/
        QObject *sender;
        /*发送者信号索引*/
        int signal_index : 27;      // In signal range (see
                                    // QObjectPrivate::signalIndex())
        /*接收者*/
        QAtomicPointer<QObject> receiver;
        /*接收者线程信息*/
        QAtomicPointer<QThreadData> receiverThreadData;
        /*接收者的槽回调函数*/
        union {
            StaticMetaCallFunction callFunction;
            QtPrivate::QSlotObjectBase *slotObj;
        };
        /*信号槽链接方式*/
        ushort connectionType : 3;  // 0 == auto, 1 == direct, 2 == queued, 4 ==
                                    // blocking
    };
};
```

* `QObject::connect` 函数将 `QObjectPrivate::Connection` 保存于 sender 中。

```shell
TestApp.exe!QObject::connect
|--  Qt5Cored.dll!QObject::connectImpl
    |--  Qt5Cored.dll!QObjectPrivate::connectImpl
```

```cpp
/*C:\Qt\Qt5.14.2\5.14.2\msvc2017_64\include\QtCore\qobject.h*/
class Q_CORE_EXPORT QObject {
    //...
    // Connect a signal to a pointer to qobject member function
    template <typename Func1, typename Func2>
    static inline QMetaObject::Connection connect(
        const typename QtPrivate::FunctionPointer<Func1>::Object *sender,
        Func1 signal,
        const typename QtPrivate::FunctionPointer<Func2>::Object *receiver,
        Func2 slot, Qt::ConnectionType type = Qt::AutoConnection) {
        //...
        return connectImpl(
            sender, reinterpret_cast<void **>(&signal), receiver,
            reinterpret_cast<void **>(&slot),
            new QtPrivate::QSlotObject<
                Func2,
                typename QtPrivate::List_Left<typename SignalType::Arguments,
                                              SlotType::ArgumentCount>::Value,
                typename SignalType::ReturnType>(slot),
            type, types, &SignalType::Object::staticMetaObject);
    }
};

// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject.cpp
QMetaObject::Connection QObject::connectImpl(
    const QObject *sender, void **signal, const QObject *receiver, void **slot,
    QtPrivate::QSlotObjectBase *slotObj, Qt::ConnectionType type,
    const int *types, const QMetaObject *senderMetaObject) {
    ...
    int signal_index = -1;
    void *args[] = {&signal_index, signal};
    for (; senderMetaObject && signal_index < 0;
         senderMetaObject = senderMetaObject->superClass()) {
        senderMetaObject->static_metacall(QMetaObject::IndexOfMethod, 0, args);
        if (signal_index >= 0 &&
            signal_index < QMetaObjectPrivate::get(senderMetaObject)->signalCount)
            break;
    }
    ...
    signal_index += QMetaObjectPrivate::signalOffset(senderMetaObject);
    return QObjectPrivate::connectImpl(sender, signal_index, receiver, slot,
                                       slotObj, type, types, senderMetaObject);
}

// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject.cpp
QMetaObject::Connection QObjectPrivate::connectImpl(
    const QObject *sender, int signal_index, const QObject *receiver,
    void **slot, QtPrivate::QSlotObjectBase *slotObj, Qt::ConnectionType type,
    const int *types, const QMetaObject *senderMetaObject) {
    ...
    QObject *s = const_cast<QObject *>(sender);
    QObject *r = const_cast<QObject *>(receiver);
    ...
    // 创建链接结构体。
    std::unique_ptr<QObjectPrivate::Connection> c{
        new QObjectPrivate::Connection};
    c->sender = s;
    c->signal_index = signal_index;
    QThreadData *td = r->d_func()->threadData;
    td->ref();
    c->receiverThreadData.storeRelaxed(td);
    c->receiver.storeRelaxed(r);
    c->slotObj = slotObj;
    c->connectionType = type;
    c->isSlotObject = true;
    if (types) {
        c->argumentTypes.storeRelaxed(types);
        c->ownArgumentTypes = false;
    }

    // 将 connection 保存在 sender 对象中。
    QObjectPrivate::get(s)->addConnection(signal_index, c.get());
    QMetaObject::Connection ret(c.release());
    ...
    return ret;
}
```

---

## 4. 信号索引

信号索引：signal_index，它是一个数组下标，便于搜索对应的信号信息；它是信号槽中非常重要的一环。

> 这个值不是三言两语能说清楚的，还是上图吧。

<div align=center><img src="/images/2023-07-27-14-12-16.png" data-action="zoom"></div>

我们先来了解一下 MOC（Meta-Object Compiler）的工作：

1. MOC 为 QObject 对象定义的信号生成对应的信号函数便于信号触发调用。
2. 生成 qt_static_metacall 处理元对象调用函数，便于获取信号对应的偏移量。
3. ...

* 测试用例代码，MOC 自动生成的 moc_TestApp.cpp 文件内容。

```cpp
// SIGNAL 0
void TestThread::sigThreadNotify(qint64 _t1, const QString &_t2) {
    void *_a[] = {
        nullptr,
        const_cast<void *>(reinterpret_cast<const void *>(std::addressof(_t1))),
        const_cast<void *>(reinterpret_cast<const void *>(std::addressof(_t2)))};
    QMetaObject::activate(this, &staticMetaObject, 0, _a);
}

void TestThread::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    ...
    else if (_c == QMetaObject::IndexOfMethod) {
        int *result = reinterpret_cast<int *>(_a[0]);
        {
            using _t = void (TestThread::*)(qint64 , const QString & );
            if (*reinterpret_cast<_t *>(_a[1]) == static_cast<_t>(&TestThread::sigThreadNotify)) {
                // 设置信号对应的索引偏移量。
                *result = 0;
                return;
            }
        }
    }
}
```

* 通过 `QObject::connect` 操作了解获取信号索引部分逻辑。

```cpp
// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject.cpp
QMetaObject::Connection QObject::connectImpl(const QObject *sender, void **signal,
                                             const QObject *receiver, void **slot,
                                             QtPrivate::QSlotObjectBase *slotObj, Qt::ConnectionType type,
                                             const int *types, const QMetaObject *senderMetaObject)
{
    ...
    int signal_index = -1;
    void *args[] = { &signal_index, signal };
    for (; senderMetaObject && signal_index < 0; senderMetaObject = senderMetaObject->superClass()) {
        // 从 TestThread::qt_static_metacall 中获取对应的 signal_index
        senderMetaObject->static_metacall(QMetaObject::IndexOfMethod, 0, args);
        if (signal_index >= 0 && signal_index < QMetaObjectPrivate::get(senderMetaObject)->signalCount)
            break;
    }

    // 有可能当前 QObject 对象有父类，父类也有默认信号或者自定义信号，所以需要经过统计，计算出合适的偏移量。
    signal_index += QMetaObjectPrivate::signalOffset(senderMetaObject);
    return QObjectPrivate::connectImpl(sender, signal_index, receiver, slot, slotObj, type, types, senderMetaObject);
}
```

---

## 5. 信号槽触发逻辑

`emit` 触发一个信号，其实就是调用一个信号函数：

> sender object -> emit signal -> signalVector[signal_index] -> connectionlist -> connection -> slot callback

* 测试用例代码。

```cpp
class TestThread : public WorkThread {
    Q_OBJECT
    
 public signals:
    // 自定义信号
    void sigThreadNotify(qint64 task, const QString& data);

 private:
    // 线程任务处理函数
    virtual void handleTask(qint64 task) override {
        emit sigThreadNotify(task, "hello world!");
    }
};
```

* 测试代码，MOC 自动生成的 moc_TestApp.cpp 文件内容。

```cpp
// moc_TestApp.cpp
// SIGNAL 0
void TestThread::sigThreadNotify(qint64 _t1, const QString &_t2) {
    void *_a[] = {
        nullptr,
        const_cast<void *>(reinterpret_cast<const void *>(std::addressof(_t1))),
        const_cast<void *>(reinterpret_cast<const void *>(std::addressof(_t2)))};
    QMetaObject::activate(this, &staticMetaObject, 0, _a);
}
```

* QT 内部开源源码，通过 signal_index 找到对应的链接表；遍历链接表，触发信号对应的槽函数。

```cpp
// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject.cpp
void QMetaObject::activate(QObject *sender, const QMetaObject *m, int local_signal_index,
                           void **argv)
{
    int signal_index = local_signal_index + QMetaObjectPrivate::signalOffset(m);

    if (Q_UNLIKELY(qt_signal_spy_callback_set.loadRelaxed()))
        doActivate<true>(sender, signal_index, argv);
    else
        doActivate<false>(sender, signal_index, argv);
}

// C:\Qt\Qt5.14.2\5.14.2\Src\qtbase\src\corelib\kernel\qobject.cpp
template <bool callbacks_enabled>
void doActivate(QObject *sender, int signal_index, void **argv) {
    QObjectPrivate *sp = QObjectPrivate::get(sender);
    QObjectPrivate::ConnectionDataPointer connections(
        sp->connections.loadRelaxed());
    QObjectPrivate::SignalVector *signalVector =
        connections->signalVector.loadRelaxed();
    ...
    // 获取 connection 列表。
    const QObjectPrivate::ConnectionList *list;
    if (signal_index < signalVector->count())
        list = &signalVector->at(signal_index);
    else
        list = &signalVector->at(-1);

    // 观察者模式：遍历 connection 列表。
    do {
        QObjectPrivate::Connection *c = list->first.loadRelaxed();
        if (!c) continue;

        do {
            QObject *const receiver = c->receiver.loadRelaxed();
            if (!receiver) continue;
            ...
            // 如果发送者和接收者处在不同线程，那么事件放到队列异步触发信号对应的槽函数。
            if ((c->connectionType == Qt::AutoConnection &&
                 !receiverInSameThread) ||
                (c->connectionType == Qt::QueuedConnection)) {
                queued_activate(sender, signal_index, c, argv);
                continue;
            }
            ...
            if (c->isSlotObject) {
                ...
                const std::unique_ptr<QtPrivate::QSlotObjectBase, Deleter> obj{
                    c->slotObj};
                {
                    // 如果发送者和接收者处在相同线程，直接调用槽函数
                    obj->call(receiver, argv);
                }
            }
        } while ((c = c->nextConnectionList.loadRelaxed()) != nullptr &&
                 c->id <= highestConnectionId);

    } while (list != &signalVector->at(-1) &&
             // start over for all signals;
             ((list = &signalVector->at(-1)), true));
    ...
}
```
