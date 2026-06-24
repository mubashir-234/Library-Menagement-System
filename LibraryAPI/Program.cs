
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Collections.Generic;
using System.Data;
using System.Threading.Tasks;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader()));
var app = builder.Build();
app.UseCors();

// ── Connection String ──────────────────────────────────────
// Change Server= to your SQL Server instance name
const string ConnStr =
    "Server=.\\SQLEXPRESS;Database=LibraryDB;Trusted_Connection=True;" +
    "TrustServerCertificate=True;";

// ── Helper: run a SELECT and return rows as list of dicts ──
static async Task<List<Dictionary<string, object>>> QueryAsync(
    string sql, Action<SqlCommand>? addParams = null)
{
    var rows = new List<Dictionary<string, object>>();
    await using var cn = new SqlConnection(ConnStr);
    await cn.OpenAsync();
    await using var cmd = new SqlCommand(sql, cn);
    addParams?.Invoke(cmd);
    await using var dr = await cmd.ExecuteReaderAsync();
    while (await dr.ReadAsync())
    {
        var row = new Dictionary<string, object>();
        for (int i = 0; i < dr.FieldCount; i++)
            row[dr.GetName(i)] = dr.IsDBNull(i) ? "" : dr.GetValue(i);
        rows.Add(row);
    }
    return rows;
}

// ── Helper: run INSERT/UPDATE/DELETE ──────────────────────
static async Task<int> ExecAsync(string sql, Action<SqlCommand>? addParams = null)
{
    await using var cn = new SqlConnection(ConnStr);
    await cn.OpenAsync();
    await using var cmd = new SqlCommand(sql, cn);
    addParams?.Invoke(cmd);
    return await cmd.ExecuteNonQueryAsync();
}

// ============================================================
//  BOOKS ENDPOINTS
// ============================================================

// GET /api/books  – all books via view
app.MapGet("/api/books", async () =>
    Results.Json(await QueryAsync("SELECT * FROM vw_BooksDetail ORDER BY Title")));

// GET /api/books/search?q=term
app.MapGet("/api/books/search", async (string q) =>
    Results.Json(await QueryAsync("EXEC sp_SearchBooks @s",
        cmd => cmd.Parameters.AddWithValue("@s", q))));

// POST /api/books  – add new book
app.MapPost("/api/books", async (HttpContext ctx) =>
{
    var d = await ctx.Request.ReadFromJsonAsync<Dictionary<string, string>>();
    if (d == null) return Results.BadRequest("Invalid data");
    try
    {
        await ExecAsync(
            @"INSERT INTO Books (ISBN,Title,AuthorID,CategoryID,PublishYear,
              TotalCopies,AvailableCopies,ShelfLocation)
              VALUES (@isbn,@title,@author,@cat,@year,@total,@total,@shelf)",
            cmd => {
                cmd.Parameters.AddWithValue("@isbn",   d["isbn"]);
                cmd.Parameters.AddWithValue("@title",  d["title"]);
                cmd.Parameters.AddWithValue("@author", int.Parse(d["authorId"]));
                cmd.Parameters.AddWithValue("@cat",    int.Parse(d["categoryId"]));
                cmd.Parameters.AddWithValue("@year",   int.Parse(d["publishYear"]));
                cmd.Parameters.AddWithValue("@total",  int.Parse(d["totalCopies"]));
                cmd.Parameters.AddWithValue("@shelf",  d["shelfLocation"]);
            });
        return Results.Ok(new { message = "Book added successfully." });
    }
    catch (Exception ex) { return Results.BadRequest(new { error = ex.Message }); }
});

// PUT /api/books/{id}
app.MapPut("/api/books/{id:int}", async (int id, HttpContext ctx) =>
{
    var d = await ctx.Request.ReadFromJsonAsync<Dictionary<string, string>>();
    if (d == null) return Results.BadRequest("Invalid data");
    await ExecAsync(
        "UPDATE Books SET Title=@t, ShelfLocation=@s, TotalCopies=@c WHERE BookID=@id",
        cmd => {
            cmd.Parameters.AddWithValue("@t",  d["title"]);
            cmd.Parameters.AddWithValue("@s",  d["shelfLocation"]);
            cmd.Parameters.AddWithValue("@c",  int.Parse(d["totalCopies"]));
            cmd.Parameters.AddWithValue("@id", id);
        });
    return Results.Ok(new { message = "Book updated." });
});

// DELETE /api/books/{id}
app.MapDelete("/api/books/{id:int}", async (int id) =>
{
    try
    {
        await ExecAsync("DELETE FROM Books WHERE BookID=@id",
            cmd => cmd.Parameters.AddWithValue("@id", id));
        return Results.Ok(new { message = "Book deleted." });
    }
    catch (Exception ex) { return Results.BadRequest(new { error = ex.Message }); }
});

// ============================================================
//  MEMBERS ENDPOINTS
// ============================================================

app.MapGet("/api/members", async () =>
    Results.Json(await QueryAsync(
        "SELECT MemberID,FullName,Email,Phone,MemberType,JoinDate,IsActive FROM Members ORDER BY FullName")));

app.MapPost("/api/members", async (HttpContext ctx) =>
{
    var d = await ctx.Request.ReadFromJsonAsync<Dictionary<string, string>>();
    if (d == null) return Results.BadRequest("Invalid data");
    try
    {
        await ExecAsync(
            "INSERT INTO Members (FullName,Email,Phone,Address,MemberType) VALUES (@n,@e,@p,@a,@t)",
            cmd => {
                cmd.Parameters.AddWithValue("@n", d["fullName"]);
                cmd.Parameters.AddWithValue("@e", d["email"]);
                cmd.Parameters.AddWithValue("@p", d.GetValueOrDefault("phone", ""));
                cmd.Parameters.AddWithValue("@a", d.GetValueOrDefault("address", ""));
                cmd.Parameters.AddWithValue("@t", d.GetValueOrDefault("memberType", "Student"));
            });
        return Results.Ok(new { message = "Member registered." });
    }
    catch (Exception ex) { return Results.BadRequest(new { error = ex.Message }); }
});

app.MapPut("/api/members/{id:int}", async (int id, HttpContext ctx) =>
{
    var d = await ctx.Request.ReadFromJsonAsync<Dictionary<string, string>>();
    if (d == null) return Results.BadRequest("Invalid data");
    await ExecAsync(
        "UPDATE Members SET FullName=@n, Phone=@p, Address=@a, IsActive=@active WHERE MemberID=@id",
        cmd => {
            cmd.Parameters.AddWithValue("@n",      d["fullName"]);
            cmd.Parameters.AddWithValue("@p",      d.GetValueOrDefault("phone", ""));
            cmd.Parameters.AddWithValue("@a",      d.GetValueOrDefault("address", ""));
            cmd.Parameters.AddWithValue("@active", d["isActive"] == "1" ? 1 : 0);
            cmd.Parameters.AddWithValue("@id",     id);
        });
    return Results.Ok(new { message = "Member updated." });
});

app.MapDelete("/api/members/{id:int}", async (int id) =>
{
    await ExecAsync("UPDATE Members SET IsActive=0 WHERE MemberID=@id",
        cmd => cmd.Parameters.AddWithValue("@id", id));
    return Results.Ok(new { message = "Member deactivated." });
});

// ============================================================
//  BORROWINGS ENDPOINTS
// ============================================================

// GET all active borrowings via view
app.MapGet("/api/borrowings", async () =>
    Results.Json(await QueryAsync("SELECT * FROM vw_ActiveBorrowings ORDER BY DueDate")));

// GET full history
app.MapGet("/api/borrowings/history", async () =>
    Results.Json(await QueryAsync(
        @"SELECT br.BorrowID, m.FullName, b.Title, br.BorrowDate, br.DueDate,
                 br.ReturnDate, br.Status
          FROM Borrowings br
          JOIN Members m ON br.MemberID=m.MemberID
          JOIN Books   b ON br.BookID=b.BookID
          ORDER BY br.BorrowDate DESC")));

// POST /api/borrowings  – borrow via stored procedure
app.MapPost("/api/borrowings", async (HttpContext ctx) =>
{
    var d = await ctx.Request.ReadFromJsonAsync<Dictionary<string, string>>();
    if (d == null) return Results.BadRequest("Invalid data");
    var result = await QueryAsync("EXEC sp_BorrowBook @bookId, @memberId, @days",
        cmd => {
            cmd.Parameters.AddWithValue("@bookId",   int.Parse(d["bookId"]));
            cmd.Parameters.AddWithValue("@memberId", int.Parse(d["memberId"]));
            cmd.Parameters.AddWithValue("@days",     int.Parse(d.GetValueOrDefault("dueDays", "14")));
        });
    var row = result.Count > 0 ? result[0] : new Dictionary<string, object>();
    return row.GetValueOrDefault("Result","")?.ToString() == "SUCCESS"
        ? Results.Ok(row) : Results.BadRequest(row);
});

// POST /api/borrowings/{id}/return  – return via stored procedure
app.MapPost("/api/borrowings/{id:int}/return", async (int id) =>
{
    var result = await QueryAsync("EXEC sp_ReturnBook @borrowId",
        cmd => cmd.Parameters.AddWithValue("@borrowId", id));
    var row = result.Count > 0 ? result[0] : new Dictionary<string, object>();
    return row.GetValueOrDefault("Result","")?.ToString() == "SUCCESS"
        ? Results.Ok(row) : Results.BadRequest(row);
});

// ============================================================
//  AUTHORS & CATEGORIES (for dropdowns)
// ============================================================

app.MapGet("/api/authors", async () =>
    Results.Json(await QueryAsync(
        "SELECT AuthorID, FirstName+' '+LastName AS Name FROM Authors ORDER BY LastName")));

app.MapGet("/api/categories", async () =>
    Results.Json(await QueryAsync("SELECT CategoryID, CategoryName FROM Categories ORDER BY CategoryName")));

// ============================================================
//  FINES
// ============================================================

app.MapGet("/api/fines", async () =>
    Results.Json(await QueryAsync(
        @"SELECT f.FineID, m.FullName, b.Title, f.FineAmount,
                 f.PaidStatus, f.PaidDate, br.BorrowDate, br.DueDate
          FROM Fines f
          JOIN Borrowings br ON f.BorrowID=br.BorrowID
          JOIN Members m ON br.MemberID=m.MemberID
          JOIN Books   b ON br.BookID=b.BookID
          ORDER BY f.PaidStatus, f.FineID DESC")));

app.MapPut("/api/fines/{id:int}/pay", async (int id) =>
{
    await ExecAsync(
        "UPDATE Fines SET PaidStatus=1, PaidDate=GETDATE() WHERE FineID=@id",
        cmd => cmd.Parameters.AddWithValue("@id", id));
    return Results.Ok(new { message = "Fine marked as paid." });
});

// ============================================================
//  REPORTS (Join-based queries)
// ============================================================

app.MapGet("/api/reports/overdue", async () =>
    Results.Json(await QueryAsync(
        @"SELECT m.FullName, m.Email, m.Phone, b.Title,
                 br.DueDate, DATEDIFF(DAY,br.DueDate,GETDATE()) AS DaysOverdue
          FROM Borrowings br
          JOIN Members m ON br.MemberID=m.MemberID
          JOIN Books   b ON br.BookID=b.BookID
          WHERE br.Status IN ('Borrowed','Overdue') AND br.DueDate < GETDATE()
          ORDER BY DaysOverdue DESC")));

app.MapGet("/api/reports/popular", async () =>
    Results.Json(await QueryAsync(
        @"SELECT b.Title, a.FirstName+' '+a.LastName AS Author,
                 COUNT(br.BorrowID) AS TimesBorrowed
          FROM Borrowings br
          JOIN Books   b ON br.BookID  =b.BookID
          JOIN Authors a ON b.AuthorID =a.AuthorID
          GROUP BY b.Title, a.FirstName, a.LastName
          ORDER BY TimesBorrowed DESC")));

app.MapGet("/api/reports/dashboard", async () =>
{
    var stats = await QueryAsync(
        @"SELECT
            (SELECT COUNT(*) FROM Books)     AS TotalBooks,
            (SELECT COUNT(*) FROM Members WHERE IsActive=1) AS ActiveMembers,
            (SELECT COUNT(*) FROM Borrowings WHERE Status='Borrowed') AS CurrentlyBorrowed,
            (SELECT COUNT(*) FROM Borrowings WHERE Status='Overdue'
                OR (Status='Borrowed' AND DueDate < GETDATE())) AS OverdueCount,
            (SELECT ISNULL(SUM(FineAmount),0) FROM Fines WHERE PaidStatus=0) AS PendingFines");
    return Results.Json(stats.Count > 0 ? stats[0] : new Dictionary<string, object>());
});

app.Run("http://localhost:5000");
