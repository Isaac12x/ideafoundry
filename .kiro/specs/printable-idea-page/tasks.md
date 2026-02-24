# Implementation Plan

- [ ] 1. Create Ideas controller and routing

  - Generate IdeasController with show and print actions
  - Add RESTful routes for ideas with custom print route
  - Implement user and idea finding logic consistent with existing patterns
  - _Requirements: 1.1, 1.2_

- [ ] 2. Create basic idea show page with print link

  - Create `app/views/ideas/show.html.erb` template
  - Display idea title, description, and metadata
  - Add "Print" or "Printable View" button/link to print action
  - Style the show page consistently with existing application design
  - _Requirements: 1.1_

- [ ] 3. Create print layout template

  - Create `app/views/layouts/print.html.erb` layout file
  - Remove navigation, headers, and non-essential UI elements
  - Set up basic HTML structure optimized for printing
  - Include print-specific meta tags and viewport settings
  - _Requirements: 1.3, 5.2_

- [ ] 4. Implement print view template structure

  - Create `app/views/ideas/print.html.erb` template
  - Implement header section with logo placeholder and last updated date
  - Add title and "Project Page" label rows
  - Include conditional type/category display
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ] 5. Add image and status display section

  - Implement left column for design/render image display
  - Add image handling with Active Storage integration
  - Create right column for status information display
  - Format status as "DATE: status" entries using idea state and timestamps
  - Add placeholder handling for missing images
  - _Requirements: 3.1, 3.2, 3.3, 3.4_

- [ ] 6. Create information sections layout

  - Implement "Description" section with rich text content
  - Add "Other information" section displaying TRL, difficulty, opportunity, timing scores
  - Create "Further development" section for additional notes or future plans
  - Format each section with labels and content boxes as specified
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 7. Implement print-specific CSS styling

  - Create print stylesheet with `@media print` queries
  - Set appropriate margins, typography, and spacing for print
  - Hide navigation and non-essential elements in print view
  - Ensure high contrast and readability for black and white printing
  - Optimize page breaks and layout flow
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 8. Add helper methods for print formatting

  - Create helper methods for status history formatting
  - Implement date formatting for print display
  - Add methods for handling missing data gracefully
  - Create image handling helpers for print layout
  - _Requirements: 2.1, 3.2, 4.4_

- [ ] 9. Write controller and integration tests

  - Create controller tests for IdeasController show and print actions
  - Test routing to print action works correctly
  - Verify correct template and layout rendering
  - Test user association and idea finding logic
  - Add tests for missing idea handling (404 scenarios)
  - _Requirements: 1.1, 1.2, 1.3_

- [ ] 10. Write view and helper tests
  - Test print template renders all required sections
  - Verify helper methods format data correctly
  - Test image display and placeholder handling
  - Ensure print layout maintains structure with various data scenarios
  - Test responsive behavior and print CSS application
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4_
