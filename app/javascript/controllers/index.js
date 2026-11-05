// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application";

// The lock shortcut must work from the first moment of a page: this controller is registered statically, in the same
// module graph as Stimulus, instead of waiting on a lazy import() like the rest. (eagerLoadControllersFrom skips
// identifiers that are already registered.)
import TypingActivityController from "controllers/typing_activity_controller";
application.register("typing-activity", TypingActivityController);

// Eager load all controllers defined in the import map under controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading";
eagerLoadControllersFrom("controllers", application);

// Lazy load controllers as they appear in the DOM (remember not to preload controllers in import map!)
// import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
// lazyLoadControllersFrom("controllers", application)
