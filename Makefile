EXTENSION = pg_message_queue
DATA = pg_message_queue--0.1.sql pg_message_queue--0.2.sql pg_message_queue--0.1--0.2.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
