-- E-commerce case study: database schema (SQLite; also runs on MySQL/PostgreSQL with minor type changes)
DROP TABLE IF EXISTS shipments; DROP TABLE IF EXISTS order_items; DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products; DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
  customer_id         TEXT PRIMARY KEY,
  city                TEXT NOT NULL,
  state               TEXT NOT NULL,
  region              TEXT NOT NULL,          -- North, South, East, West, Central
  signup_date         DATE NOT NULL,
  acquisition_channel TEXT NOT NULL,
  gender              TEXT
);
CREATE TABLE products (
  product_id    TEXT PRIMARY KEY,
  product_name  TEXT NOT NULL,
  category      TEXT NOT NULL,
  sub_category  TEXT NOT NULL,
  list_price    INTEGER NOT NULL,             -- rupees
  unit_cost     INTEGER NOT NULL              -- rupees
);
CREATE TABLE orders (
  order_id       TEXT PRIMARY KEY,
  customer_id    TEXT NOT NULL REFERENCES customers(customer_id),
  order_datetime DATETIME NOT NULL,
  order_status   TEXT NOT NULL CHECK (order_status IN ('Delivered','Cancelled','Returned')),
  payment_method TEXT NOT NULL,
  coupon_code    TEXT                         -- NULL when no coupon was used
);
CREATE TABLE order_items (
  order_id        TEXT NOT NULL REFERENCES orders(order_id),
  product_id      TEXT NOT NULL REFERENCES products(product_id),
  quantity        INTEGER NOT NULL,
  unit_price      INTEGER NOT NULL,           -- rupees, price at time of order
  discount_amount REAL NOT NULL,              -- rupees off this line
  PRIMARY KEY (order_id, product_id)
);
CREATE TABLE shipments (
  order_id       TEXT PRIMARY KEY REFERENCES orders(order_id),
  courier        TEXT NOT NULL,
  shipped_date   DATE NOT NULL,
  delivered_date DATE NOT NULL,
  promised_date  DATE NOT NULL
);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_items_product ON order_items(product_id);
