# Design Document

## Overview

The printable idea page feature will add a new controller action and view template that renders individual ideas in a print-optimized format. The design leverages Rails' existing MVC architecture and integrates with the current Idea model structure, which includes rich text descriptions, attachments, state management, and metadata tracking.

## Architecture

### Controller Layer

- **New IdeasController**: Create a dedicated controller to handle individual idea operations
- **Print Action**: Add a `print` action that renders the printable view
- **Route Configuration**: Add RESTful routes for ideas with a custom print route

### View Layer

- **Print Template**: Create `app/views/ideas/print.html.erb` with the specified layout structure
- **Print Stylesheet**: Create dedicated CSS for print media queries
- **Responsive Layout**: Ensure the layout works for both screen preview and actual printing

### Model Integration

- **Existing Idea Model**: Leverage current attributes (title, description, state, created_at, updated_at, category, attachments)
- **Status History**: Utilize state transitions and timestamps for status tracking
- **Image Handling**: Use Active Storage attachments for design/render images

## Components and Interfaces

### IdeasController

```ruby
class IdeasController < ApplicationController
  before_action :set_user
  before_action :set_idea, only: [:show, :print]

  def show
    # Standard idea view with print link
  end

  def print
    # Print-optimized view
    render layout: 'print'
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:id])
  end

  def set_user
    @user = User.first || User.create!(email: 'user@example.com', name: 'Default User')
  end
end
```

### Print Layout Structure

1. **Header Section**

   - Logo placement (top-left): Application logo or placeholder
   - Last updated date (top-right): `@idea.updated_at`
   - Title row: `@idea.title`
   - Project page label: Static "Project Page" text
   - Type row: `@idea.category` if present

2. **Content Section**

   - **Left Column**: Design/render image from `@idea.attachments`
   - **Right Column**: Status information formatted as date-status pairs

3. **Information Sections**
   - **Description**: `@idea.description` (rich text)
   - **Other Information**: Additional metadata (TRL, difficulty, opportunity, timing scores)
   - **Further Development**: Custom field or notes section

### Data Models Integration

#### Status History Tracking

Since the current model tracks state changes but not detailed history, we'll display:

- Current state with last updated timestamp
- Creation date as initial status
- State transitions can be inferred from `attempt_count` and current `state`

#### Image Handling

- Primary design image: First attachment with image content type
- Fallback: Placeholder image or empty space with border
- Image sizing: Constrained to fit left column layout

#### Metadata Display

- **TRL Score**: Technology Readiness Level (0-10)
- **Difficulty**: Implementation difficulty (0-10)
- **Opportunity**: Market opportunity (0-10)
- **Timing**: Market timing (0-10)
- **Computed Score**: Overall calculated score

## Error Handling

### Missing Data Scenarios

- **No Logo**: Display application name as text header
- **No Image**: Show placeholder or maintain layout spacing
- **Empty Sections**: Display section headers with empty formatted boxes
- **Missing Metadata**: Show "Not specified" or leave blank appropriately

### Access Control

- **User Association**: Ensure ideas belong to current user
- **404 Handling**: Graceful handling of non-existent ideas
- **Permission Checks**: Validate user can access the idea

## Testing Strategy

### Unit Tests

- **Controller Tests**: Verify print action renders correctly
- **Model Tests**: Ensure existing idea model methods work as expected
- **Helper Tests**: Test any new formatting helpers for print layout

### Integration Tests

- **Print Route**: Test routing to print action
- **Layout Rendering**: Verify correct template and layout usage
- **Data Display**: Ensure all required data appears in print view

### System Tests

- **Print Functionality**: Test print button/link from idea view
- **Layout Integrity**: Verify print layout maintains structure
- **Cross-browser**: Test print preview in different browsers

### Print-Specific Tests

- **CSS Media Queries**: Verify print styles apply correctly
- **Page Breaks**: Test page break behavior for long content
- **Print Preview**: Validate appearance in browser print preview

## Implementation Notes

### Print Optimization

- **Print CSS**: Use `@media print` queries to hide navigation and optimize typography
- **Page Margins**: Set appropriate margins for physical printing
- **Font Sizing**: Use print-friendly font sizes and weights
- **Color Handling**: Ensure content is readable in black and white

### Performance Considerations

- **Image Optimization**: Resize images appropriately for print
- **Minimal JavaScript**: Avoid JavaScript dependencies in print view
- **Fast Loading**: Optimize for quick rendering of print preview

### Accessibility

- **Semantic HTML**: Use proper heading hierarchy and semantic elements
- **Alt Text**: Ensure images have descriptive alt attributes
- **Print Contrast**: Maintain sufficient contrast for print readability
