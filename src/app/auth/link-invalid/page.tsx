export default function LinkInvalidPage() {
  return (
    <main style={{ maxWidth: 480 }}>
      <h1>This link cannot be used</h1>
      <p>
        Invitation links work once and expire after an hour. If you already set your password,{" "}
        <a href="/login">sign in</a>. Otherwise ask an administrator to send a new invitation.
      </p>
    </main>
  );
}
