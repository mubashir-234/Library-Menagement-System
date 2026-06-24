# Library Management System
## CS2231 – Database Management System Lab Project

---

## Project Structure

```
library_system/
├── database/
│   └── LibraryDB.sql       ← Run this first in SQL Server
├── backend/
│   └── LibraryAPI.cs       ← C# ASP.NET Web API (copy into Program.cs)
└── frontend/
    └── index.html          ← Open in browser
```

---

## DBMS Requirements Fulfilled

| Requirement                        | Implementation                                              |
|------------------------------------|-------------------------------------------------------------|
| ≥ 6 related tables                 | Authors, Categories, Books, Members, Borrowings, Fines      |
| Primary & Foreign Keys             | All tables have PKs; FK constraints with referential integrity |
| Normalized to 3NF                  | No partial/transitive dependencies across all 6 tables      |
| DDL & DML operations               | CREATE TABLE, INSERT, UPDATE, DELETE all included           |
| ≥ 5 join-based reports             | Reports 1–5 at bottom of SQL script                         |
| ≥ 2 Views                          | vw_BooksDetail, vw_ActiveBorrowings                         |
| ≥ 3 Stored Procedures              | sp_BorrowBook, sp_ReturnBook, sp_SearchBooks                |
| ≥ 3 Subqueries                     | Members with >1 borrow, never-borrowed books, below-avg copies |
| ≥ 2 Triggers                       | trg_UpdateOverdueStatus, trg_PreventBookDelete              |
| ≥ 1 Transaction (COMMIT/ROLLBACK)  | Inside sp_BorrowBook and sp_ReturnBook                      |
| UI CRUD operations                 | Add/Delete Books, Register/Deactivate Members, Borrow/Return |
| Validation                         | CHK constraints in DB + required fields in UI               |

---

## Setup Steps

### Step 1 – Run the Database Script
1. Open **SQL Server Management Studio (SSMS)**
2. Open `database/LibraryDB.sql`
3. Press **F5** to run — this creates `LibraryDB` with all tables, views, SPs, triggers, and sample data

### Step 2 – Set Up the C# Backend
```bash
# Create project
dotnet new webapi -n LibraryAPI --no-openapi
cd LibraryAPI

# Install SQL Server package
dotnet add package Microsoft.Data.SqlClient

# Replace contents of Program.cs with LibraryAPI.cs content
# Then run:
dotnet run
```
> The API runs on **http://localhost:5000**

> If your SQL Server instance is not the default `.`, update the `ConnStr` at the top of `LibraryAPI.cs`:
> ```
> Server=YOUR_SERVER_NAME;Database=LibraryDB;Trusted_Connection=True;TrustServerCertificate=True;
> ```

### Step 3 – Open the Frontend
- Simply open `frontend/index.html` in any browser (Chrome, Edge, Firefox)
- No web server needed — it calls the API directly

---

## UI Features

| Page       | Operations                                      |
|------------|-------------------------------------------------|
| Dashboard  | Live stats + active borrowings overview         |
| Books      | Add book, search by title/author/ISBN, delete   |
| Members    | Register member, view all, deactivate           |
| Borrow     | Issue book (calls sp_BorrowBook via API)        |
| Returns    | Return book + auto fine calculation             |
| Fines      | View all fines, mark as paid                    |
| Reports    | Overdue books report, most popular books        |

---

## Tech Stack
- **Database:** SQL Server (LibraryDB)
- **Backend:** C# ASP.NET Core Minimal API
- **Frontend:** Plain HTML + CSS + JavaScript (no frameworks)
- **Connection:** ADO.NET via Microsoft.Data.SqlClient
