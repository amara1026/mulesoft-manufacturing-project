CREATE TABLE IF NOT EXISTS idempotency_record (
  idempotency_key VARCHAR(64) PRIMARY KEY,
  request_hash VARCHAR(64) NOT NULL,
  status VARCHAR(20) NOT NULL,
  http_status INT,
  response_body VARCHAR(16000),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS order_state (
  order_id VARCHAR(40) PRIMARY KEY,
  external_order_id VARCHAR(40) NOT NULL,
  customer_id VARCHAR(20) NOT NULL,
  status VARCHAR(30) NOT NULL,
  sap_order_number VARCHAR(20),
  reservation_id VARCHAR(40),
  version INT DEFAULT 0 NOT NULL,
  order_json VARCHAR(16000),
  lines_json VARCHAR(16000),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS outbox_event (
  event_id VARCHAR(64) PRIMARY KEY,
  aggregate_id VARCHAR(40) NOT NULL,
  event_type VARCHAR(60) NOT NULL,
  payload VARCHAR(16000) NOT NULL,
  status VARCHAR(20) DEFAULT 'PENDING' NOT NULL,
  attempts INT DEFAULT 0 NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  published_at TIMESTAMP
);
CREATE TABLE IF NOT EXISTS inbox_event (
  event_id VARCHAR(64) NOT NULL,
  consumer VARCHAR(60) NOT NULL,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id, consumer)
);
CREATE TABLE IF NOT EXISTS procurement_request (
  business_key VARCHAR(120) PRIMARY KEY,
  order_id VARCHAR(40) NOT NULL,
  material_number VARCHAR(40) NOT NULL,
  quantity DECIMAL(15,3) NOT NULL,
  status VARCHAR(20) NOT NULL,
  requisition_number VARCHAR(20),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS dead_letter_event (
  id VARCHAR(64) PRIMARY KEY,
  source_queue VARCHAR(60) NOT NULL,
  error_type VARCHAR(120),
  error_description VARCHAR(2000),
  message VARCHAR(16000) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  replayed_at TIMESTAMP
);
