---
name: one-by-one
description: Asks the user the decisions work is waiting on one at a time, each with the context and links needed to answer it, recording each answer before asking the next. Use for "one by one" or a backlog of decisions.
license: GPL-3.0. Full text at https://www.gnu.org/licenses/gpl-3.0.html
compatibility: Any Claude surface. Works best in Claude Code or another agent that can read the project's files and commit the answers it records.
metadata:
  author: Super Speedy Plugins
  version: "1.0.0"
---

# One by one

A summary that ends with five open questions gets skimmed, and the questions get answered partly or
not at all. Ask them one at a time instead. Each question comes with everything the user needs to
decide it, so they never have to scroll back, open a document only to find out what it's about, or
ask "what was that again?".

## 1. Collect every open question first

Before asking anything, list every decision the work is waiting on:

- Items on the "waiting on you" list from this conversation, including ones raised earlier and not
  yet answered.
- Open questions in the plans and docs for the current work (plan documents, reviews marked as
  pending, decision records).
- Anything you would otherwise decide on a guess. If it materially changes design, behaviour, data,
  compatibility or scope, it's a question for the user. If it doesn't, decide it yourself and don't
  ask.

Drop anything the user has already answered. Then order the list so that:

1. blockers come first: the ones that hold up a merge, a release or someone else's work;
2. a question comes before any question whose wording depends on its answer;
3. related questions sit next to each other, so the context carries over.

Say how many questions there are in one line ("4 questions, the database ones first"), then ask the
first. Don't list them all up front: that's the wall of text this skill exists to avoid.

## 2. Ask exactly one question per message

Each question has this shape. Keep it tight, and cut any section that adds nothing.

```
**Question 2 of 5: <the decision, as a short title>**

<What is being decided, in one or two sentences, in plain words.>

**Context**
- Why this came up: <the work, the finding, and how it was found>.
- Current state: <exact state, e.g. written, committed, pushed (repo and branch), deployed>.
- What it affects: <who or what changes depending on the answer, with numbers where you have them>.

**Options**
1. <Option> (recommended): <what happens, cost, risk>
2. <Option>: <what happens, cost, risk>

**Read more**
- <full file path or full URL>: <one line on what it holds and which section matters>

**After you answer:** <what you'll do next for each option>
```

If your tools include a way to ask a multiple-choice question (Claude Code's AskUserQuestion, for
example), use it for the same question: one question, two to four options, the recommended one
first. When the answer is free text (a name, a figure, a wording), just ask in prose.

Rules for the content:

- **Every link is complete and clickable.** A full file path (with `:line` when you mean a line), a
  full issue URL or a full site URL. Never "see the review doc".
- **Summarise the document; don't just point at it.** Give the substance in two or three lines, plus
  the evidence, so the user can answer from the message and open the document only to check.
- **Recommend, and say why in one clause.** Don't offer options you'd argue against.
- **Use exact states and exact numbers.** Not "done" or "shipped", but which of written, committed,
  pushed, deployed or released.
- **No preamble** before the question, and after the first one, no recap of earlier answers.

## 3. Record each answer before asking the next

As soon as the user answers:

1. **Write the answer down where it belongs**, so it survives the session ending: the approval line
   of a review, the open-questions section of a plan, a comment on the issue. Commit it if the
   project is in Git.
2. **Act at once only if it's quick and the next questions don't depend on it.** Otherwise note it as
   next work and keep asking. A long job never waits on the next question: start it in the
   background, then ask.
3. **If an answer settles or removes later questions,** re-plan the rest and say so in one line
   ("That settles question 4 as well").
4. **"Skip" or "later" is an answer.** Leave the item on the waiting list and move on. Never ask the
   same question twice in one run.

Then ask the next question.

## 4. Finish

After the last question, do the work the answers unblocked. When it's done, recap what changed, and
end with the items still waiting (only the skipped ones now).
