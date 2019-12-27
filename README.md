# CQRS

An Implementation of Command Queuing Responsibility Segregation and Event Sourcing.

Changes to the data model are made with events, these are persisted to provide a replayable history of changes.  Events can be undone by new events, but never "deleted" from the system.  This makes the result completely auditable, and allows off-line data creation without creating conflicts.  When multiple events are combined the resulting changes must be tested for conflicts and those resolved once all event sources are on-line to the same shared storage.  In cases where the off-line work is not shared between users, then this system allows for just the changes since the last sync to be saved upon reconnection to the cloud or other persistent store outside the active device.

Events are stored locally to a file, and asyncronously to iCloud.  This minimizes the chance of lost data, and allows off-line persistence followed by sync when connections are available.
