# Requirements Document

## Introduction

Idea Foundry is a single-user application designed to help entrepreneurs and innovators capture rough ideas and systematically evolve them into viable products. The application provides a comprehensive workflow for idea management, from initial capture through validation and development tracking.

The system supports idea versioning (similar to git commits), scoring mechanisms, clustering capabilities, and email ingestion. Users can organize ideas into lists, track their lifecycle through various states, and export their entire workspace for backup or migration purposes.

**Primary User**: Individual entrepreneur or product manager (single admin)
**Technology Stack**: Ruby on Rails 8.1, SQLite, Hotwire (Turbo/Stimulus), Active Storage, Action Mailbox, Solid Queue, Solid Cache

## Requirements

### Requirement 1: Idea Management

**User Story:** As an entrepreneur, I want to create, edit, and organize my ideas in lists, so that I can systematically track and develop my concepts.

#### Acceptance Criteria

1. WHEN I create a new idea THEN the system SHALL save it with a title, description, and timestamp
2. WHEN I edit an idea THEN the system SHALL update the content and record the modification time
3. WHEN I delete an idea THEN the system SHALL soft-delete it and move it to an archived state
4. WHEN I create a list THEN the system SHALL allow me to name it and add ideas to it
5. WHEN I drag an idea between lists THEN the system SHALL update the idea's list membership
6. WHEN I apply filters THEN the system SHALL display ideas matching the selected criteria (state, TRL, score, tags, date, attachments)

### Requirement 2: Visual Idea Organization

**User Story:** As a user, I want to arrange ideas spatially in a cluster view, so that I can visualize relationships and group related concepts.

#### Acceptance Criteria

1. WHEN I switch to cluster view THEN the system SHALL display ideas as draggable cards on a canvas
2. WHEN I drag a card to a new position THEN the system SHALL save the coordinates
3. WHEN I create a cluster region THEN the system SHALL allow me to name it and define its boundaries
4. WHEN I zoom or pan the canvas THEN the system SHALL maintain card positions relative to the viewport
5. WHEN I select multiple cards THEN the system SHALL allow bulk operations like moving to clusters

### Requirement 3: Idea Lifecycle Management

**User Story:** As a product developer, I want to track ideas through development states with automatic cool-off periods, so that I can manage my development process systematically.

#### Acceptance Criteria

1. WHEN I create an idea THEN the system SHALL set its initial state to 'new'
2. WHEN I transition an idea to 'first_try' or 'second_try' THEN the system SHALL increment the attempt count
3. WHEN an attempt fails THEN the system SHALL set a cool-off period and lock editing except for notes
4. WHEN a cool-off period expires THEN the system SHALL automatically reopen the idea for editing
5. WHEN I view an idea's timeline THEN the system SHALL display all state transitions with timestamps

### Requirement 4: Comprehensive Idea Details

**User Story:** As a user, I want a detailed view of each idea with rich content and metadata, so that I can fully develop and evaluate my concepts.

#### Acceptance Criteria

1. WHEN I open an idea THEN the system SHALL display the title, category, status, and timestamps in the header
2. WHEN I upload a hero image THEN the system SHALL display it prominently on the left side
3. WHEN I view idea stats THEN the system SHALL show TRL, Difficulty, Opportunity, Timing, and computed Score
4. WHEN I switch between tabs THEN the system SHALL display Description, Media & Notes, or Metadata content
5. WHEN I view the timeline THEN the system SHALL show version history and next steps at the bottom

### Requirement 5: Version Control

**User Story:** As a user, I want to version my ideas like git commits, so that I can track changes and restore previous versions without losing work.

#### Acceptance Criteria

1. WHEN I save changes to an idea THEN the system SHALL create a new version with a parent pointer
2. WHEN I create a version THEN the system SHALL snapshot the current state as JSON
3. WHEN I compare versions THEN the system SHALL display differences side-by-side
4. WHEN I restore a previous version THEN the system SHALL create a new branch without destroying the current version
5. WHEN I view version history THEN the system SHALL show a timeline with diff summaries

### Requirement 6: Email Integration

**User Story:** As a busy entrepreneur, I want to create ideas by sending emails, so that I can capture thoughts quickly from anywhere.

#### Acceptance Criteria

1. WHEN I send an email to the ingestion address THEN the system SHALL create a new idea with subject as title and body as description
2. WHEN I include attachments in the email THEN the system SHALL save them as idea media
3. WHEN I include `[IDEA-123]` in the subject THEN the system SHALL append the content to the existing idea
4. WHEN I include `#category: X` in the email THEN the system SHALL assign the specified category
5. WHEN an unauthorized sender emails THEN the system SHALL reject the message

### Requirement 7: Template System

**User Story:** As a user, I want to create templates for different types of ideas, so that I can maintain consistency and ensure I capture all necessary information.

#### Acceptance Criteria

1. WHEN I create a template THEN the system SHALL allow me to define section order and custom metadata fields
2. WHEN I apply a template to an idea THEN the system SHALL reorder the UI according to the template structure
3. WHEN I set a default template THEN the system SHALL apply it to new ideas automatically
4. WHEN I validate an idea against a template THEN the system SHALL check for required metadata fields
5. WHEN I have multiple templates THEN the system SHALL allow me to choose which one to apply

### Requirement 8: Scoring System

**User Story:** As a product evaluator, I want to score ideas based on multiple factors, so that I can prioritize which concepts to pursue.

#### Acceptance Criteria

1. WHEN I adjust scoring sliders THEN the system SHALL update TRL, Difficulty, Opportunity, and Timing values (0-10)
2. WHEN scoring factors change THEN the system SHALL recalculate the total score using the configured formula
3. WHEN I modify scoring weights in settings THEN the system SHALL apply the new formula to all ideas
4. WHEN I create a new version THEN the system SHALL snapshot the current scoring values
5. WHEN I view historical scores THEN the system SHALL display how scoring has changed over time

### Requirement 9: Data Export

**User Story:** As a user, I want to export my entire workspace, so that I can backup my data or migrate to another system.

#### Acceptance Criteria

1. WHEN I initiate an export THEN the system SHALL create a job to package the database, files, and metadata
2. WHEN the export completes THEN the system SHALL provide a downloadable archive with manifest.json and README_IMPORT.md
3. WHEN I enable password protection THEN the system SHALL encrypt the archive with the provided password
4. WHEN the export is processing THEN the system SHALL display progress updates
5. WHEN the export fails THEN the system SHALL provide clear error messages and retry options

### Requirement 10: System Configuration

**User Story:** As an administrator, I want to configure system settings, so that I can customize the application behavior to my preferences.

#### Acceptance Criteria

1. WHEN I access settings THEN the system SHALL allow me to configure email ingestion parameters
2. WHEN I modify templates THEN the system SHALL save changes and apply them to future ideas
3. WHEN I adjust scoring weights THEN the system SHALL update the calculation formula
4. WHEN I edit lifecycle states THEN the system SHALL allow customization of state names and cool-off durations
5. WHEN I manage exports THEN the system SHALL show export history and allow new export creation

### Requirement 11: Data Management

**User Story:** As a user, I want to safely delete ideas while maintaining the ability to recover them, so that I can clean up my workspace without permanent data loss.

#### Acceptance Criteria

1. WHEN I delete an idea THEN the system SHALL move it to an archived state rather than permanently removing it
2. WHEN I view archived ideas THEN the system SHALL display them separately from active ideas
3. WHEN I restore an archived idea THEN the system SHALL return it to its previous active state
4. WHEN I permanently purge an idea THEN the system SHALL warn me and require confirmation
5. WHEN I purge an idea THEN the system SHALL remove all associated versions and media files

## Non-Functional Requirements

### Performance and Scalability

- The system SHALL support up to 10,000 ideas per workspace without performance degradation
- The cluster view SHALL render smoothly with up to 500 visible cards
- Export operations SHALL complete within 5 minutes for workspaces up to 1GB

### Technology Constraints

- The system SHALL be built using Ruby on Rails 8.1 with Hotwire (Turbo/Stimulus)
- The system SHALL use SQLite as the primary database
- The system SHALL use Active Storage for file management
- The system SHALL use Action Mailbox for email ingestion
- The system SHALL use Action Text for rich text descriptions
- The system SHALL use Solid Queue and Solid Cache for background jobs and caching

### Security

- The system SHALL encrypt sensitive metadata using Active Record encryption
- The system SHALL validate and sanitize all email inputs to prevent security vulnerabilities
- The system SHALL require authentication for all application access

### Accessibility

- The system SHALL comply with WCAG 2.1 AA accessibility standards
- The system SHALL support keyboard navigation for all interactive elements
- The system SHALL provide appropriate ARIA labels and semantic HTML

### Testing and Quality

- The system SHALL maintain test coverage using Minitest and Capybara for system tests
- The system SHALL validate all user inputs and provide clear error messages
- The system SHALL handle graceful degradation when JavaScript is disabled

## Open Questions

The following questions need resolution during the design phase:

1. **List Membership**: Should ideas belong to one list only (Kanban style) or multiple lists (tag style)?
2. **Score Display**: Should scores display as raw floats (0-10) or rounded integers?
3. **Additional Screen**: Should the third main screen be Calendar/Timeline, Asset Library, or Insights Dashboard?
4. **Export Encryption**: Should exports use AES-encrypted tarball or AES-Zip with external tools?
5. **Email Provider**: Should the system support bring-your-own email provider (Mailgun/Postmark) or start with local inbox?
6. **Template Complexity**: Do templates need conditional field visibility based on other field values?
7. **File Constraints**: What size and type constraints should apply to attachments?
8. **Cool-off Durations**: What are the recommended default durations for attempt cool-off periods?
9. **Authentication Method**: Should authentication use password login, passkey, or environment-based local secret?
