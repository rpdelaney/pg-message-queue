## PostgreSQL Message Queue
This software implements a very simple message queue framework on PostgreSQL
for use in integrating software using relatively loosely coupled setups.
Applications include:

 * Queuing emails to be sent on commits that meet some specific criteria
 * Queuing other info that is to be sent to a remote application, perhaps for
   web service requests
 * Sending messages to other systems (perhaps a gateway to RabbitMQ or the
   like?)

## Installation
To install the extension so that PostgreSQL can find it:

```sh
make install
```

If you are using Linux with distro-supplied packages you may need to install
the development packages.

Then in psql, pgAdmin, or the like, run the following SQL query:

```sql
CREATE EXTENSION pg_message_queue;
```

## Usage
This extension is based on the idea of channels.  Each channel is a queue.
Messages are sent to the queue and expected to be delivered at some later time.
There is no guarantee or expectation that messages will be immediately
delivered.  The messages could be stored and then retrieved in a nightly
cronjob, using a listener, or some other method.  The aim here is flexibility.

The internal implementation is handled in ``pg_mq_config_catalog``.  This stores the
physical location of the queue tables, channels, etc.  By default, the tables
are named ``pg_mq_queue_[channel]`` so that conflicts of names are not an issue.

## Creating a queue
To create a queue, use the function:

```sql
pg_mq_create_queue(in_channel text, in_type text)
```

Currently ``in_type`` can be any of 'bytea', 'text', or 'xml.'  Note further that by
default public is not given access to this function so it should be run as a
superuser, or perms to this function should be granted to those who need it.  An
example of usage might be:

```sql
SELECT * FROM pg_mq_create_queue('test_queue', 'text');
```

Each queue table is created with a trigger which notifies any listener of any
inserts into the queue.  You can listen by:

```sql
LISTEN "test_queue";
```

And you will receive asynchronous notifications when a new item is added.
Listening is not required, of course.  You can connect to the queue periodically
to pull batches.  That is perfectly supported, of course.  But LISTEN gives you
the option of greater interactivity between components, if you need it.

You can then manage permissions on the underlying tables.

## Sending messages
Sending messages to the queue is done using the function:

```sql
pg_mq_send_message(in_channel text, in_payload anyelement)
```

Example:

```sql
SELECT * FROM pg_mq_send_message('test_queue', 'Read This'::text);
```

## Retrieving messages
This then allows you to retrieve it using one of the following two functions:

```sql
pg_mq_get_msg_bin(in_channel name, in_num_messages int)
pg_mq_get_msg_text(in_channel name, in_num_messages int)
```

The first casts the payload to bytea, which works with all queue types, and the
second casts to text, which works for all other than bytea queues.

In all cases it sends you ``msg_id``, ``sent_by`` (username), ``was_delivered``, and
``payload``.

Sending and receiving messages requires that permissions are granted to
underlying tables.

<!--
vim: ft=markdown
-->
