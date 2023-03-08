const std = @import("std");
const assert = std.debug.assert;

/// Many producer, many consumer, non-allocating, thread-safe.
/// Uses a mutex to protect access.
/// The queue does not manage ownership and the user is responsible to
/// manage the storage of the nodes.
pub fn SizedAtomicQueue(comptime T: type) type {
    return struct {
        head: ?*Node,
        tail: ?*Node,
        mutex: std.Thread.Mutex,
        size: usize,
        max_size: usize,
        // we use a condition variable to block the producer when the queue is full
        cond: std.Thread.Condition,

        pub const Self = @This();
        pub const Node = std.TailQueue(T).Node;

        /// Initializes a new queue. The queue does not provide a `deinit()`
        /// function, so the user must take care of cleaning up the queue elements.
        pub fn init(max_size: usize) Self {
            return Self{
                .head = null,
                .tail = null,
                .mutex = .{},
                .size = 0,
                .cond = .{},
                .max_size = max_size,
            };
        }

        /// Appends `node` to the queue.
        /// The lifetime of `node` must be longer than lifetime of queue.
        pub fn put(self: *Self, node: *Node) void {
            node.next = null;

            self.mutex.lock();
            defer self.mutex.unlock();

            const thread_id = std.Thread.getCurrentId();
            std.log.debug("[thread {}] putting node 0x{x} into queue", .{ thread_id, @ptrToInt(node) });

            // wait until there is space in the queue
            while (self.size >= self.max_size) {
                std.log.debug("[thread {}] queue is full, waiting...", .{thread_id});
                self.cond.wait(&self.mutex);
            }

            node.prev = self.tail;
            self.tail = node;
            if (node.prev) |prev_tail| {
                prev_tail.next = node;
            } else {
                assert(self.head == null);
                self.head = node;
            }

            self.size += 1;
        }

        /// Gets a previously inserted node or returns `null` if there is none.
        /// It is safe to `get()` a node from the queue while another thread tries
        /// to `remove()` the same node at the same time.
        pub fn get(self: *Self) ?*Node {
            self.mutex.lock();
            defer self.mutex.unlock();

            const head = self.head orelse return null;
            self.head = head.next;
            if (head.next) |new_head| {
                new_head.prev = null;
            } else {
                self.tail = null;
            }
            // This way, a get() and a remove() are thread-safe with each other.
            head.prev = null;
            head.next = null;

            self.size -= 1;
            defer {
                std.log.debug("[thread {}] got node 0x{x} from queue, signaling", .{ std.Thread.getCurrentId(), @ptrToInt(head) });
                self.cond.signal();
            }

            return head;
        }

        /// Prepends `node` to the front of the queue.
        /// The lifetime of `node` must be longer than the lifetime of the queue.
        pub fn unget(self: *Self, node: *Node) void {
            node.prev = null;

            self.mutex.lock();
            defer self.mutex.unlock();

            self.size += 1;
            // signal the producer that there is space in the queue
            if (self.size < self.max_size) {
                self.cond.signal();
            }

            const opt_head = self.head;
            self.head = node;
            if (opt_head) |old_head| {
                node.next = old_head;
            } else {
                assert(self.tail == null);
                self.tail = node;
            }
        }

        /// Removes a node from the queue, returns whether node was actually removed.
        /// It is safe to `remove()` a node from the queue while another thread tries
        /// to `get()` the same node at the same time.
        pub fn remove(self: *Self, node: *Node) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (node.prev == null and node.next == null and self.head != node) {
                return false;
            }

            if (node.prev) |prev| {
                prev.next = node.next;
            } else {
                self.head = node.next;
            }
            if (node.next) |next| {
                next.prev = node.prev;
            } else {
                self.tail = node.prev;
            }
            node.prev = null;
            node.next = null;

            self.size -= 1;
            if (self.size < self.max_size) {
                self.cond.signal();
            }
            return true;
        }

        /// Returns `true` if the queue is currently empty.
        /// Note that in a multi-consumer environment a return value of `false`
        /// does not mean that `get` will yield a non-`null` value!
        pub fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.head == null;
        }

        /// Dumps the contents of the queue to `stderr`.
        pub fn dump(self: *Self) void {
            self.dumpToStream(std.io.getStdErr().writer()) catch return;
        }

        /// Dumps the contents of the queue to `stream`.
        /// Up to 4 elements from the head are dumped and the tail of the queue is
        /// dumped as well.
        pub fn dumpToStream(self: *Self, stream: anytype) !void {
            const S = struct {
                fn dumpRecursive(
                    s: anytype,
                    optional_node: ?*Node,
                    indent: usize,
                    comptime depth: comptime_int,
                ) !void {
                    try s.writeByteNTimes(' ', indent);
                    if (optional_node) |node| {
                        try s.print("0x{x}={}\n", .{ @ptrToInt(node), node.data });
                        if (depth == 0) {
                            try s.print("(max depth)\n", .{});
                            return;
                        }
                        try dumpRecursive(s, node.next, indent + 1, depth - 1);
                    } else {
                        try s.print("(null)\n", .{});
                    }
                }
            };
            self.mutex.lock();
            defer self.mutex.unlock();

            try stream.print("head: ", .{});
            try S.dumpRecursive(stream, self.head, 0, 4);
            try stream.print("tail: ", .{});
            try S.dumpRecursive(stream, self.tail, 0, 4);
        }
    };
}
