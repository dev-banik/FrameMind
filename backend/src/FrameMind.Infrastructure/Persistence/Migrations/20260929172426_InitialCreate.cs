using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace FrameMind.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    FirebaseUid = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    PhotoUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    Plan = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_users", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "device_tokens",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Token = table.Column<string>(type: "character varying(4096)", maxLength: 4096, nullable: false),
                    Platform = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    LastSeenAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_device_tokens", x => x.Id);
                    table.ForeignKey(
                        name: "FK_device_tokens_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "projects",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_projects", x => x.Id);
                    table.ForeignKey(
                        name: "FK_projects_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "chats",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProjectId = table.Column<Guid>(type: "uuid", nullable: true),
                    Title = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    UserPrompt = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    VideoUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: false),
                    ThumbnailUrl = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    Language = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    DurationSeconds = table.Column<int>(type: "integer", nullable: false),
                    Style = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    VoiceType = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    Analysis = table.Column<string>(type: "jsonb", nullable: false),
                    Script = table.Column<string>(type: "jsonb", nullable: true),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_chats", x => x.Id);
                    table.ForeignKey(
                        name: "FK_chats_projects_ProjectId",
                        column: x => x.ProjectId,
                        principalTable: "projects",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_chats_users_UserId",
                        column: x => x.UserId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "generated_videos",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ChatId = table.Column<Guid>(type: "uuid", nullable: false),
                    StorageKey = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    ThumbnailKey = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    Resolution = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    DurationSeconds = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_generated_videos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_generated_videos_chats_ChatId",
                        column: x => x.ChatId,
                        principalTable: "chats",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "generation_jobs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ChatId = table.Column<Guid>(type: "uuid", nullable: false),
                    Resolution = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    Stage = table.Column<string>(type: "character varying(30)", maxLength: 30, nullable: false),
                    Progress = table.Column<int>(type: "integer", nullable: false),
                    Error = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    VideoId = table.Column<Guid>(type: "uuid", nullable: true),
                    StartedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_generation_jobs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_generation_jobs_chats_ChatId",
                        column: x => x.ChatId,
                        principalTable: "chats",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_chats_ProjectId",
                table: "chats",
                column: "ProjectId");

            migrationBuilder.CreateIndex(
                name: "IX_chats_UserId_CreatedAt",
                table: "chats",
                columns: new[] { "UserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_device_tokens_Token",
                table: "device_tokens",
                column: "Token",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_device_tokens_UserId",
                table: "device_tokens",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_generated_videos_ChatId_CreatedAt",
                table: "generated_videos",
                columns: new[] { "ChatId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_generation_jobs_ChatId_CreatedAt",
                table: "generation_jobs",
                columns: new[] { "ChatId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_generation_jobs_CreatedAt",
                table: "generation_jobs",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_projects_UserId_CreatedAt",
                table: "projects",
                columns: new[] { "UserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_users_FirebaseUid",
                table: "users",
                column: "FirebaseUid",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "device_tokens");

            migrationBuilder.DropTable(
                name: "generated_videos");

            migrationBuilder.DropTable(
                name: "generation_jobs");

            migrationBuilder.DropTable(
                name: "chats");

            migrationBuilder.DropTable(
                name: "projects");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
