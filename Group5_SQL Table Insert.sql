-- =====================
-- SCHEMA DEFINITION
-- =====================

-- 1. Locations
CREATE TABLE locations (
    location_id   SERIAL PRIMARY KEY,
    location_name VARCHAR(100) UNIQUE,
    address       VARCHAR(255),
    city          VARCHAR(100),
    state         CHAR(2),
    zip_code      VARCHAR(10),
    opened_date   DATE,
    type          VARCHAR(20)
        CHECK (type IN ('Queens','Brooklyn','Manhattan','Other'))
);

-- 2. Suppliers
CREATE TABLE suppliers (
    supplier_id     SERIAL PRIMARY KEY,
    supplier_name   VARCHAR(100) NOT NULL,
    supplier_rating NUMERIC(3,2)
        CHECK (supplier_rating BETWEEN 0 AND 5),
    email           VARCHAR(100) UNIQUE,
    phone_number    VARCHAR(20),
    notes           TEXT
);

-- 3. Manufacturers
CREATE TABLE manufacturers (
    manufacturer_id   SERIAL PRIMARY KEY,
    manufacturer_name VARCHAR(100) NOT NULL,
    email             VARCHAR(100),
    phone_number      VARCHAR(20),
    notes             TEXT
);

-- 4. Products
CREATE TABLE products (
    product_id      SERIAL PRIMARY KEY,
    product_name    VARCHAR(100) NOT NULL,
    category        VARCHAR(50),
    unit_cost       DECIMAL(10,2) NOT NULL,
    unit_price      DECIMAL(10,2) NOT NULL,
    expiration_days INT,
    manufacturer_id INT NOT NULL
        REFERENCES manufacturers(manufacturer_id),
    supplier_id     INT NOT NULL
        REFERENCES suppliers(supplier_id)
);

-- 5. Purchase Orders
CREATE TABLE purchase_orders (
    purchase_order_id SERIAL PRIMARY KEY,
    supplier_id       INT NOT NULL
        REFERENCES suppliers(supplier_id),
    location_id       INT NOT NULL
        REFERENCES locations(location_id),
    order_date        DATE NOT NULL,
    delivery_date     DATE,
    status            VARCHAR(20)
        CHECK (status IN ('Ordered','Received','Cancelled'))
);

-- 6. Deliveries
CREATE TABLE deliveries (
    delivery_id            SERIAL PRIMARY KEY,
    purchase_order_id      INT NOT NULL
        REFERENCES purchase_orders(purchase_order_id),
    supplier_id            INT NOT NULL
        REFERENCES suppliers(supplier_id),
    expected_delivery_date DATE,
    delivery_date          DATE,
    status                 VARCHAR(20)
        CHECK (status IN ('Scheduled','Delivered','Delayed'))
);

-- 7. Purchase Order Details
CREATE TABLE purchase_order_details (
    purchase_order_detail_id SERIAL PRIMARY KEY,
    purchase_order_id        INT NOT NULL
        REFERENCES purchase_orders(purchase_order_id),
    product_id               INT NOT NULL
        REFERENCES products(product_id),
    quantity                 INT NOT NULL,
    unit_cost                DECIMAL(10,2)
);

-- 8. Inventory
CREATE TABLE inventory (
    inventory_id      SERIAL PRIMARY KEY,
    product_id        INT NOT NULL
        REFERENCES products(product_id),
    location_id       INT NOT NULL
        REFERENCES locations(location_id),
    quantity          INT NOT NULL,
    entry_date        DATE NOT NULL,
    expiration_date   DATE,
    purchase_order_id INT
        REFERENCES purchase_orders(purchase_order_id),
    delivery_id       INT
        REFERENCES deliveries(delivery_id)
);

-- 9. Employees
CREATE TABLE employees (
    employee_id    SERIAL PRIMARY KEY,
    location_id    INT NOT NULL
        REFERENCES locations(location_id),
    first_name     VARCHAR(50) NOT NULL,
    last_name      VARCHAR(50) NOT NULL,
    department     VARCHAR(50),
    hourly_wage    NUMERIC(5,2),
    hours_per_week NUMERIC(5,2),
    hire_date      DATE,
    notes          TEXT
);

-- 10. Staffing
CREATE TABLE staffing (
    staffing_id  SERIAL PRIMARY KEY,
    employee_id  INT NOT NULL
        REFERENCES employees(employee_id),
    location_id  INT NOT NULL
        REFERENCES locations(location_id),
    shift_date   DATE NOT NULL,
    start_time   TIME NOT NULL,
    end_time     TIME NOT NULL,
    status       VARCHAR(20) DEFAULT 'scheduled'
);

-- 11. Customers
CREATE TABLE customers (
    customer_id    SERIAL PRIMARY KEY,
    first_name     VARCHAR(50),
    last_name      VARCHAR(50),
    age            INT,
    gender         CHAR(1)
        CHECK (gender IN ('M','F','O')),
    email          VARCHAR(100),
    location_id    INT NOT NULL
        REFERENCES locations(location_id),
    loyalty_member BOOLEAN DEFAULT FALSE
);

-- 12. Promotions
CREATE TABLE promotions (
    promotion_id        SERIAL PRIMARY KEY,
    promotion_name      VARCHAR(100),
    start_date          DATE NOT NULL,
    end_date            DATE NOT NULL,
    location_id         INT NOT NULL
        REFERENCES locations(location_id),
    discount_percentage NUMERIC(4,2) NOT NULL,
    loyalty_only        BOOLEAN DEFAULT FALSE
);

-- 13. Sales Orders
CREATE TABLE sales_orders (
    sales_orders_id SERIAL PRIMARY KEY,
    order_date      DATE NOT NULL,
    location_id     INT NOT NULL
        REFERENCES locations(location_id),
    customer_id     INT
        REFERENCES customers(customer_id),
    total_amount    DECIMAL(10,2)
);

-- 14. Sales Orders Details
CREATE TABLE sales_orders_details (
    sales_orders_detail_id SERIAL PRIMARY KEY,
    sales_orders_id        INT NOT NULL
        REFERENCES sales_orders(sales_orders_id),
    product_id             INT NOT NULL
        REFERENCES products(product_id),
    quantity               INT NOT NULL,
    unit_price             DECIMAL(10,2) NOT NULL,
    discount               DECIMAL(5,2) DEFAULT 0,
    promotion_id           INT
        REFERENCES promotions(promotion_id)
);

-- 15. Expenses
CREATE TABLE expenses (
    expense_id   SERIAL PRIMARY KEY,
    category     VARCHAR(50) NOT NULL,
    amount       DECIMAL(10,2) NOT NULL,
    expense_date DATE NOT NULL,
    location_id  INT
        REFERENCES locations(location_id),
    supplier_id  INT
        REFERENCES suppliers(supplier_id),
    description  TEXT
);

-- 16. Returns
CREATE TABLE returns (
    return_id               SERIAL PRIMARY KEY,
    sales_orders_detail_id  INT NOT NULL
        REFERENCES sales_orders_details(sales_orders_detail_id),
    quantity_returned       INT NOT NULL,
    return_date             DATE,
    reason                  TEXT
);


-- =====================
-- TRIGGERS & FUNCTIONS
-- =====================

-- 1) Update delivery status
CREATE OR REPLACE FUNCTION update_delivery_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.delivery_date IS NULL THEN
    RETURN NEW;
  ELSIF NEW.expected_delivery_date IS NULL
     OR NEW.delivery_date <= NEW.expected_delivery_date THEN
    NEW.status := 'Delivered';
  ELSE
    NEW.status := 'Delayed';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_delivery_status
  BEFORE UPDATE OF delivery_date ON deliveries
  FOR EACH ROW
  EXECUTE FUNCTION update_delivery_status();

-- 2) Update inventory entry_date
CREATE OR REPLACE FUNCTION update_inventory_entry_date()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE inventory
    SET entry_date = NEW.delivery_date
    WHERE delivery_id = NEW.delivery_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_inventory_entry_date
  AFTER UPDATE OF delivery_date ON deliveries
  FOR EACH ROW
  WHEN (NEW.delivery_date IS NOT NULL)
  EXECUTE FUNCTION update_inventory_entry_date();

-- 3) Recalculate sales total
CREATE OR REPLACE FUNCTION update_sales_total()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE sales_orders
    SET total_amount = (
      SELECT SUM((unit_price - unit_price * discount / 100) * quantity)
      FROM sales_orders_details
      WHERE sales_orders_id = NEW.sales_orders_id
    )
  WHERE sales_orders_id = NEW.sales_orders_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_sales_total
  AFTER INSERT OR UPDATE OR DELETE ON sales_orders_details
  FOR EACH ROW
  EXECUTE FUNCTION update_sales_total();

-- 4) Set inventory expiration
CREATE OR REPLACE FUNCTION set_inventory_expiration()
RETURNS TRIGGER AS $$
BEGIN
  SELECT NEW.entry_date + (p.expiration_days || ' days')::INTERVAL
    INTO NEW.expiration_date
    FROM products p
   WHERE p.product_id = NEW.product_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_inventory_expiration
  BEFORE INSERT ON inventory
  FOR EACH ROW
  EXECUTE FUNCTION set_inventory_expiration();

-- 5a) Upsert inventory on delivery
CREATE OR REPLACE FUNCTION upsert_inventory_from_delivery()
RETURNS TRIGGER AS $$
DECLARE
  v_loc INT;
  prod RECORD;
BEGIN
  SELECT location_id INTO v_loc
  FROM purchase_orders
  WHERE purchase_order_id = NEW.purchase_order_id;

  FOR prod IN
    SELECT product_id, quantity
    FROM purchase_order_details
    WHERE purchase_order_id = NEW.purchase_order_id
  LOOP
    UPDATE inventory
      SET quantity   = inventory.quantity + prod.quantity,
          entry_date = NEW.delivery_date
    WHERE product_id = prod.product_id
      AND location_id = v_loc;

    IF NOT FOUND THEN
      INSERT INTO inventory (
        product_id, location_id, quantity,
        entry_date, expiration_date,
        purchase_order_id, delivery_id
      )
      SELECT
        prod.product_id,
        v_loc,
        prod.quantity,
        NEW.delivery_date,
        NEW.delivery_date + (p.expiration_days || ' days')::INTERVAL,
        NEW.purchase_order_id,
        NEW.delivery_id
      FROM products p
      WHERE p.product_id = prod.product_id;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_add_inventory_on_delivery_insert
  AFTER INSERT ON deliveries
  FOR EACH ROW
  WHEN (NEW.status = 'Delivered')
  EXECUTE FUNCTION upsert_inventory_from_delivery();

CREATE TRIGGER trg_add_inventory_on_delivery_update
  AFTER UPDATE OF status ON deliveries
  FOR EACH ROW
  WHEN (NEW.status = 'Delivered')
  EXECUTE FUNCTION upsert_inventory_from_delivery();

-- 5b) Subtract inventory on sale
CREATE OR REPLACE FUNCTION subtract_inventory_on_sale()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE inventory
    SET quantity = quantity - NEW.quantity
  WHERE product_id  = NEW.product_id
    AND location_id = (
      SELECT location_id
      FROM sales_orders
      WHERE sales_orders_id = NEW.sales_orders_id
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_subtract_inventory_on_sale
  AFTER INSERT ON sales_orders_details
  FOR EACH ROW
  EXECUTE FUNCTION subtract_inventory_on_sale();

-- 6) Create supplier rating based on late deliveries
ALTER TABLE suppliers
ADD COLUMN IF NOT EXISTS delivery_rating NUMERIC(3, 2) DEFAULT NULL; -- Allows values like 4.50

COMMENT ON COLUMN suppliers.delivery_rating IS 'Calculated rating (0-5) based on on-time delivery performance (5=best). NULL if not calculated yet or no completed deliveries.';

-- Drop the function if it exists, allowing us to modify and recreate it.
DROP FUNCTION IF EXISTS update_supplier_delivery_rating() CASCADE; -- CASCADE drops dependent triggers

CREATE OR REPLACE FUNCTION update_supplier_delivery_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_supplier_id INT;
    total_completed_deliveries INT := 0; -- Initialize to zero
    late_completed_deliveries INT := 0; -- Initialize to zero
    late_percentage NUMERIC := 0.0; -- Initialize to zero
    new_rating NUMERIC(3, 2) := NULL; -- Default rating is NULL
BEGIN
    -- Determine the relevant supplier_id based on the operation (INSERT, UPDATE, DELETE)
    IF (TG_OP = 'DELETE') THEN
        -- If a delivery record is deleted, get the supplier_id from the OLD record
        v_supplier_id := OLD.supplier_id;
        -- If the deleted delivery was 'Delivered', we need to recalculate
        IF OLD.status <> 'Delivered' THEN
             -- If the deleted record wasn't a completed delivery, no rating change needed
             RETURN OLD; -- Exit trigger for DELETE operations on non-delivered items
        END IF;
    ELSE
        -- For INSERT or UPDATE, get the supplier_id from the NEW record
        v_supplier_id := NEW.supplier_id;
        -- For UPDATE, only proceed if relevant columns changed or status became 'Delivered'
        IF (TG_OP = 'UPDATE') THEN
            IF NEW.status = OLD.status AND NEW.delivery_date = OLD.delivery_date AND NEW.expected_delivery_date = OLD.expected_delivery_date AND NEW.supplier_id = OLD.supplier_id THEN
                -- If nothing relevant changed, exit trigger
                RETURN NEW;
            END IF;
            -- If the supplier ID itself changed, we need to update BOTH the old and new supplier ratings
            IF NEW.supplier_id <> OLD.supplier_id THEN
                 -- Trigger separate update for the OLD supplier ID (using a helper or direct logic)
                 PERFORM update_supplier_rating_for_id(OLD.supplier_id); -- Assumes helper function exists or add logic here
            END IF;
        END IF;
    END IF;

    -- Exit if supplier_id is somehow NULL
    IF v_supplier_id IS NULL THEN
        RAISE WARNING 'Trigger update_supplier_delivery_rating called with NULL supplier_id';
        IF (TG_OP = 'DELETE') THEN RETURN OLD; ELSE RETURN NEW; END IF;
    END IF;

    -- Calculate total completed deliveries for this supplier
    -- A delivery is considered completed if its status is 'Delivered'
    SELECT COUNT(*)
    INTO total_completed_deliveries
    FROM deliveries
    WHERE supplier_id = v_supplier_id
      AND status = 'Delivered';

    -- If there are no completed deliveries, rating remains NULL (or you could set a default)
    IF total_completed_deliveries = 0 THEN
        new_rating := NULL; -- Or potentially 5.00 if 0 deliveries means 0 late
    ELSE
        -- Calculate the number of LATE completed deliveries
        -- A completed delivery is late if the actual delivery_date is after the expected_delivery_date
        -- Handle NULL dates: Assume not late if either date is NULL
        SELECT COUNT(*)
        INTO late_completed_deliveries
        FROM deliveries
        WHERE supplier_id = v_supplier_id
          AND status = 'Delivered'
          AND delivery_date IS NOT NULL -- Must have an actual delivery date
          AND expected_delivery_date IS NOT NULL -- Must have an expected date
          AND delivery_date > expected_delivery_date; -- The actual lateness condition

        -- Calculate the late percentage
        late_percentage := late_completed_deliveries::NUMERIC / total_completed_deliveries::NUMERIC;

        -- Calculate the rating (0-5 scale, higher is better)
        -- Simple linear scale: 5 * (1 - late_percentage)
        new_rating := 5.00 * (1.0 - late_percentage);

        -- Clamp the rating between 0 and 5 just in case of calculation quirks
        IF new_rating < 0.00 THEN new_rating := 0.00; END IF;
        IF new_rating > 5.00 THEN new_rating := 5.00; END IF;

    END IF;

    -- Update the delivery_rating in the suppliers table
    UPDATE suppliers
    SET delivery_rating = new_rating -- new_rating will be NULL if no completed deliveries
    WHERE supplier_id = v_supplier_id;

    -- Return the appropriate record based on the operation
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD; -- For DELETE trigger
    ELSE
        RETURN NEW; -- For INSERT/UPDATE trigger
    END IF;

END;
$$ LANGUAGE plpgsql;

-- Helper function needed if supplier_id changes during UPDATE (optional but robust)
-- This function encapsulates the rating calculation for a specific supplier ID
CREATE OR REPLACE FUNCTION update_supplier_rating_for_id(p_supplier_id INT)
RETURNS VOID AS $$
DECLARE
    total_completed_deliveries INT := 0;
    late_completed_deliveries INT := 0;
    late_percentage NUMERIC := 0.0;
    new_rating NUMERIC(3, 2) := NULL;
BEGIN
     IF p_supplier_id IS NULL THEN RETURN; END IF;

     SELECT COUNT(*) INTO total_completed_deliveries
     FROM deliveries WHERE supplier_id = p_supplier_id AND status = 'Delivered';

     IF total_completed_deliveries = 0 THEN
         new_rating := NULL;
     ELSE
         SELECT COUNT(*) INTO late_completed_deliveries
         FROM deliveries
         WHERE supplier_id = p_supplier_id
           AND status = 'Delivered'
           AND delivery_date IS NOT NULL
           AND expected_delivery_date IS NOT NULL
           AND delivery_date > expected_delivery_date;

         late_percentage := late_completed_deliveries::NUMERIC / total_completed_deliveries::NUMERIC;
         new_rating := GREATEST(0.00, LEAST(5.00, 5.00 * (1.0 - late_percentage))); -- GREATEST/LEAST clamps 0-5
     END IF;

     UPDATE suppliers SET delivery_rating = new_rating WHERE supplier_id = p_supplier_id;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_deliveries_update_supplier_rating
AFTER INSERT OR UPDATE OR DELETE ON deliveries -- Trigger on all relevant operations
FOR EACH ROW -- Execute the function once for each affected row
EXECUTE FUNCTION update_supplier_delivery_rating();
