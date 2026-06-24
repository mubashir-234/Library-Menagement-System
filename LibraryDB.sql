-- ============================================================
--   LIBRARY MANAGEMENT SYSTEM - SQL SERVER SCRIPT
--   CS2231 Database Management System Lab
-- ============================================================
Create DATABASE LibraryDB;
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'LibraryDB')
    DROP DATABASE LibraryDB;
GO

CREATE DATABASE LibraryDB;
GO

SELECT * FROM Books;
select*from Authors;
select*from Members;
USE LibraryDB;
GO

-- ============================================================
-- DDL: CREATE TABLES (Normalized to 3NF)
-- ============================================================

-- 1. Authors Table
CREATE TABLE Authors (
    AuthorID    INT IDENTITY(1,1) PRIMARY KEY,
    FirstName   VARCHAR(50)  NOT NULL,
    LastName    VARCHAR(50)  NOT NULL,
    Country     VARCHAR(50),
    CONSTRAINT UQ_Author UNIQUE (FirstName, LastName)
);

-- 2. Categories Table
CREATE TABLE Categories (
    CategoryID   INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName VARCHAR(100) NOT NULL UNIQUE,
    Description  VARCHAR(255)
);

-- 3. Books Table
CREATE TABLE Books (
    BookID       INT IDENTITY(1,1) PRIMARY KEY,
    ISBN         VARCHAR(20)  NOT NULL UNIQUE,
    Title        VARCHAR(200) NOT NULL,
    AuthorID     INT          NOT NULL,
    CategoryID   INT          NOT NULL,
    PublishYear  INT,
    TotalCopies  INT          NOT NULL DEFAULT 1,
    AvailableCopies INT       NOT NULL DEFAULT 1,
    ShelfLocation VARCHAR(20),
    CONSTRAINT FK_Books_Author   FOREIGN KEY (AuthorID)   REFERENCES Authors(AuthorID),
    CONSTRAINT FK_Books_Category FOREIGN KEY (CategoryID) REFERENCES Categories(CategoryID),
    CONSTRAINT CHK_Copies CHECK (AvailableCopies >= 0 AND TotalCopies >= AvailableCopies)
);

-- 4. Members Table
CREATE TABLE Members (
    MemberID    INT IDENTITY(1,1) PRIMARY KEY,
    FullName    VARCHAR(100) NOT NULL,
    Email       VARCHAR(100) NOT NULL UNIQUE,
    Phone       VARCHAR(20),
    Address     VARCHAR(255),
    MemberType  VARCHAR(20)  NOT NULL DEFAULT 'Student'
                    CHECK (MemberType IN ('Student','Faculty','Public')),
    JoinDate    DATE         NOT NULL DEFAULT GETDATE(),
    IsActive    BIT          NOT NULL DEFAULT 1
);

-- 5. Borrowings Table
CREATE TABLE Borrowings (
    BorrowID    INT IDENTITY(1,1) PRIMARY KEY,
    BookID      INT  NOT NULL,
    MemberID    INT  NOT NULL,
    BorrowDate  DATE NOT NULL DEFAULT GETDATE(),
    DueDate     DATE NOT NULL,
    ReturnDate  DATE NULL,
    Status      VARCHAR(20) NOT NULL DEFAULT 'Borrowed'
                    CHECK (Status IN ('Borrowed','Returned','Overdue')),
    CONSTRAINT FK_Borrow_Book   FOREIGN KEY (BookID)   REFERENCES Books(BookID),
    CONSTRAINT FK_Borrow_Member FOREIGN KEY (MemberID) REFERENCES Members(MemberID)
);

-- 6. Fines Table
CREATE TABLE Fines (
    FineID      INT IDENTITY(1,1) PRIMARY KEY,
    BorrowID    INT            NOT NULL UNIQUE,
    FineAmount  DECIMAL(8,2)   NOT NULL DEFAULT 0,
    PaidStatus  BIT            NOT NULL DEFAULT 0,
    PaidDate    DATE           NULL,
    CONSTRAINT FK_Fine_Borrow FOREIGN KEY (BorrowID) REFERENCES Borrowings(BorrowID)
);

GO

-- ============================================================
-- VIEWS
-- ============================================================

-- View 1: All Books with Author and Category details
CREATE VIEW vw_BooksDetail AS
    SELECT b.BookID, b.ISBN, b.Title,
           a.FirstName + ' ' + a.LastName AS AuthorName,
           c.CategoryName,
           b.PublishYear, b.TotalCopies, b.AvailableCopies,
           b.ShelfLocation,
           CASE WHEN b.AvailableCopies > 0 THEN 'Available' ELSE 'Not Available' END AS Availability
    FROM Books b
    JOIN Authors   a ON b.AuthorID   = a.AuthorID
    JOIN Categories c ON b.CategoryID = c.CategoryID;
GO

-- View 2: Active Borrowings with member & book info
CREATE VIEW vw_ActiveBorrowings AS
    SELECT br.BorrowID, m.FullName AS MemberName, m.Email, m.MemberType,
           b.Title AS BookTitle, b.ISBN,
           br.BorrowDate, br.DueDate,
           DATEDIFF(DAY, br.DueDate, GETDATE()) AS DaysOverdue,
           br.Status
    FROM Borrowings br
    JOIN Members m ON br.MemberID = m.MemberID
    JOIN Books   b ON br.BookID   = b.BookID
    WHERE br.Status IN ('Borrowed','Overdue');
GO

-- ============================================================
-- STORED PROCEDURES
-- ============================================================

-- SP 1: Borrow a Book (with transaction)
CREATE PROCEDURE sp_BorrowBook
    @BookID   INT,
    @MemberID INT,
    @DueDays  INT = 14
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Check availability
        IF NOT EXISTS (SELECT 1 FROM Books WHERE BookID = @BookID AND AvailableCopies > 0)
        BEGIN
            ROLLBACK;
            SELECT 'ERROR' AS Result, 'No copies available.' AS Message;
            RETURN;
        END

        -- Check member is active
        IF NOT EXISTS (SELECT 1 FROM Members WHERE MemberID = @MemberID AND IsActive = 1)
        BEGIN
            ROLLBACK;
            SELECT 'ERROR' AS Result, 'Member is not active.' AS Message;
            RETURN;
        END

        -- Insert borrowing record
        INSERT INTO Borrowings (BookID, MemberID, BorrowDate, DueDate, Status)
        VALUES (@BookID, @MemberID, GETDATE(), DATEADD(DAY, @DueDays, GETDATE()), 'Borrowed');

        -- Reduce available copies
        UPDATE Books SET AvailableCopies = AvailableCopies - 1 WHERE BookID = @BookID;

        COMMIT;
        SELECT 'SUCCESS' AS Result, 'Book borrowed successfully.' AS Message;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        SELECT 'ERROR' AS Result, ERROR_MESSAGE() AS Message;
    END CATCH
END;
GO

-- SP 2: Return a Book
CREATE PROCEDURE sp_ReturnBook
    @BorrowID INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @BookID INT, @DueDate DATE, @Fine DECIMAL(8,2) = 0;

        SELECT @BookID = BookID, @DueDate = DueDate
        FROM Borrowings WHERE BorrowID = @BorrowID AND Status = 'Borrowed';

        IF @BookID IS NULL
        BEGIN
            ROLLBACK;
            SELECT 'ERROR' AS Result, 'Borrowing record not found or already returned.' AS Message;
            RETURN;
        END

        -- Calculate fine (10 PKR per overdue day)
        IF GETDATE() > @DueDate
            SET @Fine = DATEDIFF(DAY, @DueDate, GETDATE()) * 10.00;

        -- Update borrowing status
        UPDATE Borrowings SET ReturnDate = GETDATE(), Status = 'Returned'
        WHERE BorrowID = @BorrowID;

        -- Restore available copy
        UPDATE Books SET AvailableCopies = AvailableCopies + 1
        WHERE BookID = @BookID;

        -- Insert fine if overdue
        IF @Fine > 0
            INSERT INTO Fines (BorrowID, FineAmount, PaidStatus) VALUES (@BorrowID, @Fine, 0);

        COMMIT;
        SELECT 'SUCCESS' AS Result,
               CAST(@Fine AS VARCHAR) AS FineAmount,
               'Book returned. Fine: Rs.' + CAST(@Fine AS VARCHAR) AS Message;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        SELECT 'ERROR' AS Result, ERROR_MESSAGE() AS Message;
    END CATCH
END;
GO

-- SP 3: Search Books
CREATE PROCEDURE sp_SearchBooks
    @SearchTerm VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM vw_BooksDetail
    WHERE Title        LIKE '%' + @SearchTerm + '%'
       OR AuthorName   LIKE '%' + @SearchTerm + '%'
       OR CategoryName LIKE '%' + @SearchTerm + '%'
       OR ISBN         LIKE '%' + @SearchTerm + '%';
END;
GO

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger 1: Auto-mark borrowings as Overdue
CREATE TRIGGER trg_UpdateOverdueStatus
ON Borrowings
AFTER UPDATE
AS
BEGIN
    UPDATE Borrowings
    SET Status = 'Overdue'
    WHERE Status = 'Borrowed' AND DueDate < GETDATE();
END;
GO

-- Trigger 2: Prevent deleting a book that has active borrowings
CREATE TRIGGER trg_PreventBookDelete
ON Books
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM Borrowings br
        JOIN deleted d ON br.BookID = d.BookID
        WHERE br.Status = 'Borrowed'
    )
    BEGIN
        RAISERROR('Cannot delete a book that is currently borrowed.', 16, 1);
        ROLLBACK;
    END
    ELSE
        DELETE FROM Books WHERE BookID IN (SELECT BookID FROM deleted);
END;
GO

-- ============================================================
-- DML: SAMPLE DATA
-- ============================================================

INSERT INTO Authors (FirstName, LastName, Country) VALUES
('Robert',   'Lafore',    'USA'),
('Abraham',  'Silberschatz','USA'),
('Elmasri',  'Ramez',     'USA'),
('Herbert',  'Schildt',   'USA'),
('Andrew',   'Tanenbaum', 'Netherlands');

INSERT INTO Categories (CategoryName, Description) VALUES
('Database',       'Database systems and management'),
('Programming',    'Programming languages and software development'),
('Networking',     'Computer networks and communications'),
('Operating System','OS concepts and design'),
('Data Structures','Algorithms and data structures');

INSERT INTO Books (ISBN, Title, AuthorID, CategoryID, PublishYear, TotalCopies, AvailableCopies, ShelfLocation) VALUES
('978-0-13-468599-1', 'Database System Concepts',          2, 1, 2019, 3, 3, 'A1'),
('978-0-13-110362-7', 'Fundamentals of Database Systems',  3, 1, 2015, 2, 2, 'A2'),
('978-0-07-248250-7', 'Object-Oriented Programming in C++',1, 2, 2001, 4, 4, 'B1'),
('978-0-07-352154-5', 'Java: The Complete Reference',       4, 2, 2018, 3, 3, 'B2'),
('978-0-13-294654-2', 'Computer Networks',                  5, 3, 2010, 2, 2, 'C1');

INSERT INTO Members (FullName, Email, Phone, MemberType) VALUES
('Ali Hassan',    'ali@uni.edu',     '0300-1111111', 'Student'),
('Sara Ahmed',    'sara@uni.edu',    '0301-2222222', 'Student'),
('Dr. Kamran',    'kamran@uni.edu',  '0302-3333333', 'Faculty');

GO

-- ============================================================
-- SAMPLE JOIN-BASED QUERIES (Reports)
-- ============================================================

-- Report 1: Books with Author and Category
SELECT b.Title, a.FirstName+' '+a.LastName AS Author, c.CategoryName, b.AvailableCopies
FROM Books b
JOIN Authors a    ON b.AuthorID   = a.AuthorID
JOIN Categories c ON b.CategoryID = c.CategoryID;

-- Report 2: Member Borrowing History
SELECT m.FullName, b.Title, br.BorrowDate, br.DueDate, br.Status
FROM Borrowings br
JOIN Members m ON br.MemberID = m.MemberID
JOIN Books   b ON br.BookID   = b.BookID;

-- Report 3: Overdue Books with Member Contact
SELECT m.FullName, m.Email, m.Phone, b.Title, br.DueDate,
       DATEDIFF(DAY, br.DueDate, GETDATE()) AS DaysOverdue
FROM Borrowings br
JOIN Members m ON br.MemberID = m.MemberID
JOIN Books   b ON br.BookID   = b.BookID
WHERE br.Status IN ('Borrowed','Overdue') AND br.DueDate < GETDATE();

-- Report 4: Most Borrowed Books
SELECT b.Title, COUNT(br.BorrowID) AS TimesBorrowed
FROM Borrowings br JOIN Books b ON br.BookID = b.BookID
GROUP BY b.Title ORDER BY TimesBorrowed DESC;

-- Report 5: Fine Summary per Member
SELECT m.FullName, SUM(f.FineAmount) AS TotalFine,
       SUM(CASE WHEN f.PaidStatus=0 THEN f.FineAmount ELSE 0 END) AS PendingFine
FROM Fines f
JOIN Borrowings br ON f.BorrowID  = br.BorrowID
JOIN Members    m  ON br.MemberID = m.MemberID
GROUP BY m.FullName;

-- Subquery 1: Members who borrowed more than once
SELECT FullName FROM Members WHERE MemberID IN (
    SELECT MemberID FROM Borrowings GROUP BY MemberID HAVING COUNT(*) > 1
);

-- Subquery 2: Books never borrowed
SELECT Title FROM Books WHERE BookID NOT IN (SELECT BookID FROM Borrowings);

-- Subquery 3: Books below average available copies
SELECT Title, AvailableCopies FROM Books
WHERE AvailableCopies < (SELECT AVG(AvailableCopies) FROM Books);

PRINT 'LibraryDB created and populated successfully.';
GO
