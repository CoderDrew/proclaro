import { Card, Page, PageHeader } from "@/components/ui";

export default function LinkInvalidPage() {
  return (
    <Page width="narrow">
      <Card>
        <PageHeader title="This link cannot be used" />
        <p>
          Invitation links work once and expire after an hour. If you already set your password,{" "}
          <a href="/login">sign in</a>. Otherwise ask an administrator to send a new invitation.
        </p>
      </Card>
    </Page>
  );
}
