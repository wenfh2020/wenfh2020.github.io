---
layout: post
title:  "golang 压测 redis 消息队列"
categories: redis
tags: redis golang msglist
author: wenfh2020
---

用 redis  的 list 数据结构作为轻量级的消息队列，对于小系统确实是小而美，可控能力强。当然与 kafka 相比它还有很多缺陷。



* content
{:toc}

---

## 测试机器

机器配置：双核，4G

测试数据：100 w

---

## 生产者

生产者，生产 100 w 条数据， 并发 13817 。([测试源码](https://github.com/wenfh2020/go-test/blob/master/redis/redis_list/producer/produce.go))

```go
func Produce(szBytes []byte) (err error) {
    pConn := GetRedisConn()
    if pConn.Err() != nil {
        fmt.Println(pConn.Err().Error())
        return
    }

    defer pConn.Close()

    if _, err = pConn.Do("lpush", "redislist", szBytes); err != nil {
        fmt.Println(err.Error())
        return
    }

    return
}
```

![负载](https://raw.githubusercontent.com/wenfh2020/imgs_for_blog/master/md20200214094325.png)

```shell
begin time: 2018-07-29 14:03:55.606
end   time: 2018-07-29 14:05:07.976
Produce message: 1000000
avg: 13817.860879118389
```

---

## 消费者

消费者，消费 100 w 条数据，并发 9433。([测试源码](https://github.com/wenfh2020/go-test/blob/master/redis/redis_list/customer/logic.go))

```go
func Custom() {
    c, err := redis.Dial("tcp", REDIS_ADDR)
    if err != nil {
        fmt.Println(err)
        return
    }

    defer c.Close()

    ...

    for {
        vals, err := redis.Values(c.Do("brpop", MESSAGE_KEY, WAIT_TIME))
        if err != nil {
            ...
            time.Sleep(3 * time.Second)
            continue
        }
    }
}
```

![消费者负载](https://raw.githubusercontent.com/wenfh2020/imgs_for_blog/master/md20200214095132.png)

```shell
begin time: 2018-07-29 14:46:11.166
end time: 2018-07-29 14:47:58.038
custom message: 1000000
avg: 9433
```

---

## 总结

以上生产和消费测试都是独立测试的，生产数据和消费数据，能达到 1w 左右的并发；如果生产者和消费者同时进行工作，各自并发能力还要下降 20%左右。消费者为了保证数据被消费失败后，能保重新消费，还需要写一部分逻辑，估计性能还会下降一部分，所以单实例的Redis消息队列消费并发应该是5000左右(根据业务多开几条队列，通过性能叠加，解决更高的并发问题？！）

---

测试代码用的是 golang 第三方库 `redigo` 做的压测，如果换成 C++ 的 hiredis 异步特性（参考我的帖子[《hiredis + libev 异步测试》）](https://wenfh2020.github.io/2018/06/17/redis-hiredis-libev/)，生产者单进程并发轻松上 10w+，原则上消费能力也一样，但是消费为了保证数据的时序性，一般是一条条取出来入库处理，入库是同步操作，速度显然快不了多少。
