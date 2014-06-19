\echo Use "CREATE EXTENSION pg_message_queue" to load this file. \quit

DROP TABLE pg_mq_xml;
ALTER TABLE pg_mq_bytea RENAME TO pg_mq_bin;

ALTER TABLE pg_mq_config_catalog
 DROP CONSTRAINT "pg_mq_config_catalog_payload_type_check" ;

DROP FUNCTION pg_mq_trigger_notify();
DROP FUNCTION pg_mq_create_queue (in_channel text, in_payload_type text);
DROP FUNCTION pg_mq_drop_queue(in_channel name);
DROP FUNCTION pg_mq_send_message(in_channel text, in_payload anyelement);
DROP FUNCTION pg_mq_get_msg_text(in_channel name, in_num_msgs int);
DROP FUNCTION pg_mq_get_msg_bin(in_channel name, in_num_msgs int);
DROP FUNCTION pg_mq_get_msg_id_text(in_channel name, in_msg_id int);
DROP FUNCTION pg_mq_get_msg_id_bin(in_channel name, in_msg_id int);
DROP FUNCTION pg_mq_rebuild_triggers();

CREATE OR REPLACE FUNCTION pg_mq_trigger_notify() RETURNS TRIGGER
LANGUAGE PLPGSQL AS
$$
DECLARE t_channel name;
BEGIN
   SELECT channel INTO t_channel FROM pg_mq_config_catalog 
    WHERE table_name = TG_RELNAME;

   EXECUTE 'NOTIFY ' || quote_ident(t_channel) || ', ' 
            || quote_literal(NEW.msg_id);
   RETURN NEW;
END;
$$;

COMMENT ON FUNCTION pg_mq_trigger_notify() IS
$$ This function raises a notification on the channel specified in the 
pg_mq_config_catalog for this table.  It is looked up every time currently so
if the value is changed in that table it takes effect on db commit. $$;

CREATE OR REPLACE FUNCTION pg_mq_create_queue
(in_channel text, in_payload_type REGTYPE)
RETURNS pg_mq_config_catalog 
LANGUAGE PLPGSQL VOLATILE SECURITY DEFINER AS $$

DECLARE 
    out_val pg_mq_config_catalog%ROWTYPE;
    t_table_name name;
BEGIN

t_table_name := 'pg_mq_queue_' || in_channel;

INSERT INTO pg_mq_config_catalog (table_name, channel, payload_type)
VALUES (t_table_name, in_channel, in_payload_type);

SELECT * INTO out_val FROM pg_mq_config_catalog 
 WHERE channel = in_channel;

-- in_payload_type can't be quoted since it is a regtype, but that also makes
-- it safe.  --CT
EXECUTE 'CREATE TABLE ' || quote_ident(t_table_name) || '(
    like pg_mq_base INCLUDING ALL,
    payload ' || in_payload_type || ' NOT NULL
  )';

EXECUTE 'CREATE TRIGGER pg_mq_notify
         AFTER INSERT ON ' || quote_ident(t_table_name) || '
         FOR EACH ROW EXECUTE PROCEDURE pg_mq_trigger_notify()';

RETURN out_val;

END;
$$;

REVOKE EXECUTE ON FUNCTION pg_mq_create_queue(text, REGTYPE) FROM public;

CREATE OR REPLACE FUNCTION pg_mq_drop_queue(in_channel name) RETURNS bool
LANGUAGE plpgsql VOLATILE SECURITY DEFINER  AS $$

declare t_table_name name;

BEGIN

   SELECT table_name INTO t_table_name FROM pg_mq_config_catalog 
    WHERE channel = in_channel;

   EXECUTE 'DROP TABLE ' || quote_ident(t_table_name) || ' CASCADE';

   DELETE FROM pg_mq_config_catalog WHERE channel = in_channel;

   RETURN FOUND;

END;
$$;

REVOKE EXECUTE ON FUNCTION pg_mq_drop_queue(in_channel name) FROM public;

CREATE OR REPLACE FUNCTION pg_mq_send_message
(in_channel text, in_payload anyelement)
RETURNS pg_mq_base
LANGUAGE PLPGSQL VOLATILE AS $$
    DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
            out_val pg_mq_base%ROWTYPE;
    BEGIN
       SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;
      IF NOT FOUND THEN
         RAISE EXCEPTION 'Channel Not Found';
      END IF;

       EXECUTE 'INSERT INTO ' || quote_ident(cat_entry.table_name)
               || ' (payload) VALUES ( 
                     cast (' || quote_literal(in_payload) || ' AS ' || 
                                cat_entry.payload_type || '))
                RETURNING msg_id, sent_at, sent_by, delivered_at'
       INTO out_val ;
       RETURN out_val;
    END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_raw
(IN in_channel name, IN in_num_msgs int, IN in_raw_data anyelement,
 OUT msg_id int, OUT sent_at timestamp, OUT sent_by name, 
 OUT delivered_at timestamp, OUT payload anyelement)
RETURNS SETOF record
LANGUAGE PLPGSQL VOLATILE AS $$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;
      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = now()
              WHERE msg_id IN (SELECT msg_id 
                                 FROM $e$ || quote_ident(cat_entry.table_name) || 
                         $e$    WHERE delivered_at IS NULL
                             ORDER BY msg_id LIMIT $e$ || in_num_msgs || $e$
                             )
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload $e$;
   END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_by_id_raw
(IN in_channel name, IN in_msg_id int, IN in_raw_data anyelement,
 OUT msg_id int, OUT sent_at timestamp, OUT sent_by name, 
 OUT delivered_at timestamp, OUT payload anyelement)
RETURNS SETOF record
LANGUAGE PLPGSQL VOLATILE AS $$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;
      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = coalesce(delivered_at, now())
              WHERE msg_id = in_msg_id
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload $e$;
   END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_text
(in_channel name, in_num_msgs bigint)
RETURNS SETOF pg_mq_text
LANGUAGE PLPGSQL VOLATILE AS $$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;

   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;

      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = now()
              WHERE msg_id IN (SELECT msg_id 
                                 FROM $e$ || quote_ident(cat_entry.table_name) || 
                         $e$    WHERE delivered_at IS NULL
                             ORDER BY msg_id LIMIT $e$ || in_num_msgs || $e$
                             )
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload::text $e$;
   END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_bin
(in_channel name, in_num_msgs int)
RETURNS SETOF pg_mq_bin LANGUAGE PLPGSQL VOLATILE AS
$$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;

      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = now()
              WHERE msg_id IN (SELECT msg_id 
                                 FROM $e$ || quote_ident(cat_entry.table_name) || 
                         $e$    WHERE delivered_at IS NULL
                             ORDER BY msg_id LIMIT $e$ || in_num_msgs || $e$
                             ) 
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload::bytea $e$;
    END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_id_text
(in_channel name, in_msg_id bigint)
RETURNS SETOF pg_mq_text
LANGUAGE PLPGSQL VOLATILE AS $$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;
      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = now() 
              WHERE msg_id = $e$ || quote_literal(in_msg_id) || $e$
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload::text $e$;
    END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_get_msg_id_bin
(in_channel name, in_msg_id bigint)
RETURNS SETOF pg_mq_bin LANGUAGE PLPGSQL VOLATILE AS
$$
   DECLARE cat_entry pg_mq_config_catalog%ROWTYPE;
   BEGIN
      SELECT * INTO cat_entry FROM pg_mq_config_catalog
        WHERE channel = in_channel;
      RETURN QUERY EXECUTE
         $e$ UPDATE $e$ || quote_ident(cat_entry.table_name) || $e$
                SET delivered_at = now() 
              WHERE msg_id = $e$ || quote_literal(in_msg_id) || $e$
          RETURNING msg_id, sent_at, sent_by, delivered_at, payload::bytea $e$;
END;
$$;

CREATE OR REPLACE FUNCTION pg_mq_rebuild_triggers() returns int
LANGUAGE plpgsql AS $$
DECLARE 
    cat_val pg_mq_config_catalog%ROWTYPE;
    retval int;
BEGIN
    retval := 0;
    FOR cat_val IN  SELECT * FROM pg_mq_config_catalog 
    LOOP
       EXECUTE 'CREATE TRIGGER pg_mq_notify
         AFTER INSERT ON ' || quote_ident(t_table_name) || '
         FOR EACH ROW EXECUTE PROCEDURE pg_mq_trigger_notify()';
       retval := retval + 1;
    END LOOP;
    RETURN retval;
END;
$$;
