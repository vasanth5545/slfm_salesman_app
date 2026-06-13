-- ========================================
-- HOLIDAYS TABLE - INSERT EXAMPLES
-- ========================================
-- Use this file to insert holidays into the database
-- After inserting, the mobile app will automatically show "Holiday" status

-- ========================================
-- SINGLE HOLIDAY INSERT
-- ========================================
INSERT INTO holidays (holiday_date, reason) 
VALUES ('2026-02-14', 'Valentine Day');

-- ========================================
-- MULTIPLE HOLIDAYS INSERT (2026)
-- ========================================
INSERT INTO holidays (holiday_date, reason) VALUES
('2026-01-26', 'Republic Day'),
('2026-03-08', 'Maha Shivaratri'),
('2026-03-25', 'Holi'),
('2026-04-02', 'Good Friday'),
('2026-04-06', 'Ugadi'),
('2026-04-14', 'Tamil New Year'),
('2026-04-21', 'Ramzan'),
('2026-05-01', 'May Day'),
('2026-06-28', 'Bakrid'),
('2026-08-15', 'Independence Day'),
('2026-08-16', 'Krishna Jayanthi'),
('2026-09-05', 'Vinayagar Chaturthi'),
('2026-10-02', 'Gandhi Jayanti'),
('2026-10-24', 'Diwali'),
('2026-11-14', 'Diwali (Second Day)'),
('2026-12-25', 'Christmas');

-- ========================================
-- DELETE HOLIDAY (IF NEEDED)
-- ========================================
-- DELETE FROM holidays WHERE holiday_date = '2026-02-14';

-- ========================================
-- VIEW ALL HOLIDAYS
-- ========================================
-- SELECT * FROM holidays ORDER BY holiday_date;

-- ========================================
-- VIEW HOLIDAYS FOR SPECIFIC MONTH
-- ========================================
-- SELECT * FROM holidays WHERE DATE_FORMAT(holiday_date, '%Y-%m') = '2026-02';
