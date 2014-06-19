
\echo Use "ALTER EXTENSION pg_message_queue UPDATE" to load this file. \quit

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
                             FOR UPDATE
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
                             FOR UPDATE
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

