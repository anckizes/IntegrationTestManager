declare @fkAwareness            tinyint = 1 -- 1 = dynamically finds table dependencies and adds tables
declare @dependencyGroupCounter     int -- used to count dependency depth       

declare @tableListSubmitted table (
    schemaQualifiedObjectName	nvarchar(128)	null
    );

insert @tableListSubmitted ( schemaQualifiedObjectName )

values	('pay.payable'),('pay.payableschedule')

declare @tableListPresented table (
    SchemaQualifiedName			nvarchar(261)	null,
	TableQualifiedName 			nvarchar(261)	null,
    objectId					int				null,
    hasFkFlag                   tinyint         null,
    referencedFlag              tinyint         null,
    addedForFkFlag              tinyint         null,
    dependencyGroup             tinyint         null -- this represents the set of tables at a particular depth in the dependency chain, 0 would have no FK's
    );

insert @tableListPresented (
    SchemaQualifiedName,
	TableQualifiedName,
    objectId,
    addedForFkFlag
    )
select  SCHEMA_NAME([schema_id]) as SchemaQualifiedName,
        name as TableQualifiedName,
        [object_id]             as objectId,
        0                       as addedForFkFlag -- submitted objects were not added for FK support
from    @tableListSubmitted
        inner join
        -- This OBJECT_ID() call insures we only bring through tables
        sys.objects on objects.[object_id] = OBJECT_ID(schemaQualifiedObjectName, 'U');


if @fkAwareness = 1
begin;
    
    -- Determine if tables have any foreign keys. If so, make sure the referenced tables are
    -- added to the list, and do so recursively
    while exists (  select 1
                    from    @tableListPresented
                            inner join
                            sys.foreign_keys on foreign_keys.parent_object_id = objectId
                    where   not exists ( select 1 from @tableListPresented where objectId = foreign_keys.referenced_object_id )
                  )
    begin;
        
        insert @tableListPresented (
            SchemaQualifiedName,
			TableQualifiedName,
            objectId,
            referencedFlag,
            addedForFkFlag
            )
        -- We need to use SELECT DISTINCT to avoid adding the same table twice if another table has more
        -- than one foreign key referencing it.
        select distinct OBJECT_SCHEMA_NAME(foreign_keys.referenced_object_id) as SchemaQualifiedName,
                        OBJECT_NAME(foreign_keys.referenced_object_id) as TableQualifiedName,
                        foreign_keys.referenced_object_id,
                        1 as referencedFlag,
                        1 as addedForFkFlag
        from    sys.foreign_keys
                inner join
                @tableListPresented on objectId = foreign_keys.parent_object_id
        where   not exists ( select 1 from @tableListPresented where objectId = foreign_keys.referenced_object_id );
    
        -- Fill out missing metadata
        if exists ( select 1 from @tableListPresented where hasFkFlag is null )
        begin;
            
            -- Mark all the tables with FK's
            update  @tableListPresented
            set     hasFkFlag = 1
            where   exists ( select 1 from sys.foreign_keys where foreign_keys.parent_object_id = objectId )
                    and
                    hasFkFlag is null;
    
            -- By definition, every record left with NULL does not have an FK
            update  @tableListPresented
            set     hasFkFlag       = 0,
                    dependencyGroup = 0 -- Tables without dependencies are in dependency group 0
            where   hasFkFlag is null;
    
        end;
    
        if exists ( select 1 from @tableListPresented where referencedFlag is null )
        begin;
            
            -- Mark all the referenced tables
            update  @tableListPresented
            set     referencedFlag = 1
            where   exists (    select  1
                                from    sys.foreign_keys
                                where   foreign_keys.referenced_object_id = objectId
                                        and
                                        foreign_keys.parent_object_id in ( select objectId from @tableListPresented )
                           )
                    and
                    referencedFlag is null;
    
            -- By definition, every record left with NULL is not referenced
            update  @tableListPresented
            set     referencedFlag = 0
            where   referencedFlag is null;
    
        end;
    
    end;
    
    -- Initialize dependency group counter and determine dependency groups
    set @dependencyGroupCounter = 0;
    
    while exists ( select 1 from @tableListPresented where dependencyGroup is null )
    begin;
        
        -- Increment dependency group
        set @dependencyGroupCounter = @dependencyGroupCounter + 1;
    
        -- Identify group membership
        update  @tableListPresented
        set     dependencyGroup = @dependencyGroupCounter
        from    @tableListPresented
        where   dependencyGroup is null
                and
                (
                    not exists (
                                    select  referenced_object_id
                                    from    sys.foreign_keys
                                    where   foreign_keys.parent_object_id = objectId
    
                                    except
    
                                    select  objectId
                                    from    @tableListPresented
                                    where   dependencyGroup is not null
                                )
                    or
                    -- If a table only has a self-referencing FK, it will never trigger the above condition.
                    -- However, we also need to make sure other references are satisfied before the self-
                    -- reference is taken into consideration.
                    (
                        exists  (
                                    select  1
                                    from    sys.foreign_keys
                                    where   foreign_keys.parent_object_id = foreign_keys.referenced_object_id
                                            and
                                            foreign_keys.parent_object_id = objectId
                                )
                        and
                        not exists (
                                        select  foreign_keys.referenced_object_id
                                        from    sys.foreign_keys
                                        where   foreign_keys.parent_object_id = objectId
                                                and
                                                foreign_keys.referenced_object_id <> objectId
        
                                        except
        
                                        select  objectId
                                        from    @tableListPresented
                                        where   dependencyGroup is not null
                                    )
                    )
                );
    
    end;
    
   
    
end;



select      objectId,
            SchemaQualifiedName,
			TableQualifiedName,
            ISNULL(hasFkFlag, 0) as hasFKFlag,
            ISNULL(addedForFkFlag, 0) as addedForFkFlag
from        @tableListPresented
where       objectId is not null
order by    dependencyGroup,
            SchemaQualifiedName,
			TableQualifiedName