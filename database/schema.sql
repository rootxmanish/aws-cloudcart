-- ═══════════════════════════════════════════════════════════════
--  CloudCart — MySQL 8.0 Schema
--  Run from App EC2 after RDS is available:
--    mysql -h <RDS_ENDPOINT> -u cloudcart -p < schema.sql
--
--  Safe to re-run: all CREATE TABLE / INDEX use IF NOT EXISTS.
-- ═══════════════════════════════════════════════════════════════

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET foreign_key_checks = 0;

CREATE DATABASE IF NOT EXISTS cloudcart
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE cloudcart;

-- ── users ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id            INT          NOT NULL AUTO_INCREMENT,
    email         VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active     TINYINT(1)   NOT NULL DEFAULT 1,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── products ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
    id          INT           NOT NULL AUTO_INCREMENT,
    name        VARCHAR(255)  NOT NULL,
    description TEXT,
    price       DECIMAL(10,2) NOT NULL,
    stock       INT           NOT NULL DEFAULT 0,
    created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX ix_products_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── orders ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
    id           INT           NOT NULL AUTO_INCREMENT,
    user_id      INT           NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status       VARCHAR(50)   NOT NULL DEFAULT 'PLACED',
    created_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX ix_orders_user_id  (user_id),
    INDEX ix_orders_status   (status),
    INDEX ix_orders_created  (created_at),
    CONSTRAINT fk_orders_user
      FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── order_items ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS order_items (
    id         INT           NOT NULL AUTO_INCREMENT,
    order_id   INT           NOT NULL,
    product_id INT           NOT NULL,
    quantity   INT           NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (id),
    INDEX ix_order_items_order_id   (order_id),
    INDEX ix_order_items_product_id (product_id),
    CONSTRAINT fk_order_items_order
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_order_items_product
      FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET foreign_key_checks = 1;

-- ── Sample products (idempotent) ──────────────────────────────────
INSERT INTO products (name, description, price, stock)
SELECT 'Mechanical Keyboard', 'Full-size RGB mechanical keyboard, Cherry MX switches', 2499.00, 20
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'Mechanical Keyboard');

INSERT INTO products (name, description, price, stock)
SELECT 'Wireless Mouse', 'Ergonomic wireless mouse, 2.4 GHz, 1 year battery', 999.00, 35
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'Wireless Mouse');

INSERT INTO products (name, description, price, stock)
SELECT 'USB-C Hub', '7-in-1 USB-C hub: HDMI, USB 3.0 ×3, SD, PD charging', 1799.00, 15
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'USB-C Hub');

INSERT INTO products (name, description, price, stock)
SELECT 'Monitor Stand', 'Adjustable aluminium monitor stand with USB hub', 1299.00, 25
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'Monitor Stand');

INSERT INTO products (name, description, price, stock)
SELECT 'Laptop Sleeve 15"', 'Water-resistant neoprene sleeve for 15-inch laptops', 499.00, 50
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'Laptop Sleeve 15"');

INSERT INTO products (name, description, price, stock)
SELECT 'Webcam HD 1080p', 'Full HD webcam with built-in microphone and privacy cover', 2199.00, 12
WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = 'Webcam HD 1080p');

SELECT CONCAT('Products seeded: ', COUNT(*)) AS status FROM products;
