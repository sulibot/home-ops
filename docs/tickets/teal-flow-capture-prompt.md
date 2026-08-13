# Teal flow capture — prompt for a browser agent

Screens are already captured (home, resume builder, tracker list, job search, AI
search, all-tools, job detail). What is missing is what happens **when you click
things** — the transitions, empty states, and moments a decision gets made.

Paste everything below the line into ChatGPT with browser access, signed in to
Teal.

---

You have browser access and I am signed in to Teal at app.tealhq.com. I am doing
a UX study of the product's *flows*, not its visual design. Do not copy any
marketing text or design assets — I want to understand the sequence of steps and
what the product asks of a person at each one.

Work through the tasks below. For each, tell me **what you did, what the product
did in response, and what it asked me to decide**. Screenshot each distinct
state, including empty and error states. If something needs a paid plan, say so
and stop that task rather than upgrading.

## 1. From a job to a tailored résumé

This is the loop I care about most.

1. Open the Job Tracker and pick a saved job.
2. Find the path from that job to creating a résumé for it. Follow it.
3. Record: how much is prefilled, what it asks me to choose, whether it shows a
   match or score, and whether anything is generated that I did not write.
4. If it generates bullet points or a summary, capture the exact wording of any
   disclaimer about accuracy, and whether I must review before it is saved.

## 2. The job record's tabs

The tracker's job detail has: Job Info, Notes, Resumes, Contacts, Email
Templates, Check List, Practice Interview.

Open each. For each tab tell me: what is on it, what it looks like when empty,
what the primary action is, and whether it is free or gated.

I especially want the **Check List** and the **Guidance / "Bookmarked Steps: 0%
Complete"** element — what steps it lists, whether they differ per stage, and
whether they are generic or specific to that job.

## 3. Adding a job

Do it three ways if they exist: from the Job Search, from the AI Job Search, and
manually. Record what fields each asks for and which are required.

## 4. The keyword feature

On a job record, the description shows highlighted keywords with counts under
Requirements and Responsibilities.

Tell me: where those keywords come from, whether they are compared against my
résumé, what "Unlock 11 More Keywords" reveals, and whether anything states how
the matching works.

## 5. Onboarding, as a new user would see it

Do NOT create a new account. Instead find whatever remains of the first-run
experience: the "Getting Started" checklist on Home, the career-goal fields
(Target Title, Target Date, Target Salary Range), and any tooltips or empty
states that only appear before you have data.

Tell me what the product asks for **first**, and what it lets you skip.

## 6. Where money is asked for

List every place a free user hits a paywall, with the exact wording. I want to
know what they consider the moment of value.

## Report back as

```
TASK n — <name>
steps taken:
what the product did:
what it asked me to decide:
free / paid:
screenshots: <how many, what each shows>
notable wording: <exact quotes of anything about accuracy, AI, or review>
```

Be accurate about what you actually saw. If a flow was different from what I
described above, tell me what it really was rather than making it fit. If you
could not complete a task, say which step blocked you.
